import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/drawing.dart';
import '../painting/layer_composite_painter.dart';
import '../providers/drawing_provider.dart';

class DrawingCanvas extends StatefulWidget {
  final ValueChanged<Offset>? onTwoFingerPan;
  final void Function(Offset focalPointGlobal, double scaleDelta)?
      onTwoFingerScale;
  final Offset Function(Offset globalPoint)? toCanvas;
  final ValueChanged<bool>? onSelectionHandleInteractionChanged;
  final Size? logicalCanvasSize;
  final Offset canvasVisualOffset;
  const DrawingCanvas({
    super.key,
    this.onTwoFingerPan,
    this.onTwoFingerScale,
    this.toCanvas,
    this.onSelectionHandleInteractionChanged,
    this.logicalCanvasSize,
    this.canvasVisualOffset = Offset.zero,
  });
  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  Offset? _lastOffset;
  Size? _canvasSize;
  SelectionDragState? _dragState;
  final Map<int, Offset> _activeTouchPoints = {};
  Offset? _lastTwoFingerFocalPoint;
  double? _lastTwoFingerDistance;
  bool _ignoreDrawingGestures = false;
  int? _activeSelectionPointer;
  int? _activeDrawPointer;
  int? _activeSecondaryPointer;
  Offset? _pendingDrawStart;
  bool _activeDrawStarted = false;
  DateTime? _lastFlipTime;
  Offset? _tapDownPosition;
  static const Duration _flipDebounceDuration = Duration(milliseconds: 500);
  //もっと長い距離をかけて細くしたい場合は、以下の定数を大きくします。
  static const double _minHandleDistance = 60.0; // 入り
  static const double _rotationSoftRadius = 80.0; // 抜き（払い）は特にながく
  static const double _rotationSensitivity = 0.85;

  @override
  Widget build(BuildContext context) {
    return Consumer<DrawingProvider>(
      builder: (context, drawing, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final Size widgetSize =
                Size(constraints.maxWidth, constraints.maxHeight);
            final Size logicalSize = widget.logicalCanvasSize ?? widgetSize;
            if (_canvasSize != logicalSize) {
              _canvasSize = logicalSize;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                drawing.setCanvasSize(logicalSize);
              });
            }
            return Listener(
              onPointerDown: (event) => _handlePointerDown(event, drawing),
              onPointerMove: (event) => _handlePointerMove(event, drawing),
              onPointerUp: (event) => _handlePointerUpOrCancel(event, drawing),
              onPointerCancel: (event) =>
                  _handlePointerUpOrCancel(event, drawing),
              child: IgnorePointer(
                ignoring: _ignoreDrawingGestures,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => _handleTapDown(details),
                  onTap: () => _handleTap(drawing),
                  onPanStart: (details) => _handlePanStart(details, drawing),
                  onPanUpdate: (details) => _handlePanUpdate(details, drawing),
                  onPanEnd: (_) => _handlePanEnd(drawing),
                  onPanCancel: () => _handlePanEnd(drawing),
                  child: CustomPaint(
                    painter: DrawingPainter(
                      layerALines: drawing.layerALines,
                      layerBLines: drawing.layerBLines,
                      layerCLines: drawing.layerCLines,
                      isLayerAVisible: drawing.isLayerAVisible,
                      isLayerBVisible: drawing.isLayerBVisible,
                      isLayerCVisible: drawing.isLayerCVisible,
                      layerAOpacity: drawing.layerAOpacity,
                      layerBOpacity: drawing.layerBOpacity,
                      layerCOpacity: drawing.layerCOpacity,
                      layerABaseImage: drawing.layerABaseImage,
                      layerBBaseImage: drawing.layerBBaseImage,
                      layerCBaseImage: drawing.layerCBaseImage,
                      layerABaseSampling: drawing.layerABaseSampling,
                      layerBBaseSampling: drawing.layerBBaseSampling,
                      layerCBaseSampling: drawing.layerCBaseSampling,
                      tone30Shader: drawing.tone30Shader,
                      tone60Shader: drawing.tone60Shader,
                      tone80Shader: drawing.tone80Shader,
                      placements: drawing.placements,
                      selection: drawing.selection,
                      selectionMasksSource: drawing.selectionMasksSource,
                      selectionHandlesFilled: drawing.selectionHandlesFilled,
                      lassoDraft: drawing.lassoDraft,
                      isDrawingLasso: drawing.isDrawingLasso,
                      handles: drawing.getSelectionHandles(),
                      currentTool: drawing.currentTool,
                      shapeStart: drawing.shapeStart,
                      shapeEnd: drawing.shapeEnd,
                      canvasSize: logicalSize,
                      canvasVisualOffset: widget.canvasVisualOffset,
                    ),
                    child: Container(),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool get _isTwoFingerTouchActive => _activeTouchPoints.length >= 2;

  Offset _twoFingerFocalPoint() {
    final points = _activeTouchPoints.values.take(2).toList(growable: false);
    return Offset(
      (points[0].dx + points[1].dx) / 2,
      (points[0].dy + points[1].dy) / 2,
    );
  }

  double _twoFingerDistance() {
    final points = _activeTouchPoints.values.take(2).toList(growable: false);
    return (points[0] - points[1]).distance;
  }

  void _cancelDrawingForTwoFinger(DrawingProvider drawing) {
    _dragState = null;
    _lastOffset = null;
    _activeDrawPointer = null;
    _pendingDrawStart = null;
    _activeDrawStarted = false;
    drawing.cancelActiveInputGesture();
  }

  bool _isSecondaryMouseGesture(PointerEvent event) {
    return event.kind == ui.PointerDeviceKind.mouse &&
        (event.buttons & kSecondaryMouseButton) != 0;
  }

  void _beginSecondaryPan(PointerEvent event, DrawingProvider drawing) {
    _activeSecondaryPointer = event.pointer;
    _tapDownPosition = null;
    _cancelDrawingForTwoFinger(drawing);
  }

  Offset _toCanvasPosition(Offset globalPosition, {Offset? fallbackLocal}) {
    final mapper = widget.toCanvas;
    if (mapper != null) {
      return mapper(globalPosition);
    }
    return fallbackLocal ?? globalPosition;
  }

  bool _isInsideCanvas(Offset position) {
    final Size size = _canvasSize ?? widget.logicalCanvasSize ?? Size.zero;
    if (size == Size.zero) return false;
    return position.dx >= 0 &&
        position.dy >= 0 &&
        position.dx <= size.width &&
        position.dy <= size.height;
  }

  bool _isShapeTool(ToolType tool) {
    return tool == ToolType.rect ||
        tool == ToolType.fillRect ||
        tool == ToolType.circle ||
        tool == ToolType.fillCircle ||
        tool == ToolType.line ||
        tool == ToolType.dot30 ||
        tool == ToolType.dot60 ||
        tool == ToolType.dot80;
  }

  Offset? _canvasExitIntersection(Offset inside, Offset outside) {
    final Size size = _canvasSize ?? widget.logicalCanvasSize ?? Size.zero;
    if (size == Size.zero) return null;

    final double dx = outside.dx - inside.dx;
    final double dy = outside.dy - inside.dy;
    if (dx == 0 && dy == 0) return null;

    double t0 = 0.0;
    double t1 = 1.0;

    bool clipTest(double p, double q) {
      if (p == 0) return q >= 0;
      final double r = q / p;
      if (p < 0) {
        if (r > t1) return false;
        if (r > t0) t0 = r;
      } else {
        if (r < t0) return false;
        if (r < t1) t1 = r;
      }
      return true;
    }

    if (!clipTest(-dx, inside.dx)) return null;
    if (!clipTest(dx, size.width - inside.dx)) return null;
    if (!clipTest(-dy, inside.dy)) return null;
    if (!clipTest(dy, size.height - inside.dy)) return null;

    final double t = t1;
    return Offset(
      inside.dx + dx * t,
      inside.dy + dy * t,
    );
  }

  void _syncIgnoreDrawingGestures() {
    final bool shouldIgnore = _isTwoFingerTouchActive ||
        _activeSecondaryPointer != null ||
        _activeSelectionPointer != null ||
        _activeDrawPointer != null;
    if (_ignoreDrawingGestures == shouldIgnore) return;
    setState(() {
      _ignoreDrawingGestures = shouldIgnore;
    });
  }

  void _setSelectionHandleInteraction(bool isActive, {int? pointer}) {
    final bool wasActive = _activeSelectionPointer != null;
    _activeSelectionPointer = isActive ? pointer : null;
    if (wasActive != isActive) {
      widget.onSelectionHandleInteractionChanged?.call(isActive);
    }
    _syncIgnoreDrawingGestures();
  }

  bool _beginSelectionHandleDrag(
      PointerDownEvent event, DrawingProvider drawing) {
    if (drawing.currentTool != ToolType.lasso || drawing.selection == null) {
      return false;
    }
    final pos = _toCanvasPosition(
      event.position,
      fallbackLocal: event.localPosition,
    );
    final handle = drawing.hitTestSelection(
      pos,
      handleRadius: 24,
    );
    if (handle == SelectionHandle.none) {
      return false;
    }
    if (handle == SelectionHandle.mirror) {
      final now = DateTime.now();
      if (_lastFlipTime == null ||
          now.difference(_lastFlipTime!) > _flipDebounceDuration) {
        drawing.flipSelectionHorizontal();
        _lastFlipTime = now;
      }
      _dragState = null;
      _setSelectionHandleInteraction(true, pointer: event.pointer);
      return true;
    }

    drawing.beginSelectionInteraction();

    final sel = drawing.selection!;
    _dragState = SelectionDragState(
      handle: handle,
      startGlobal: pos,
      startLocal: sel.toLocal(pos),
      initialTranslation: sel.translation,
      initialScaleX: sel.scaleX,
      initialScaleY: sel.scaleY,
      initialRotation: sel.rotation,
    );
    _setSelectionHandleInteraction(true, pointer: event.pointer);
    return true;
  }

  bool _beginPointerDrawing(PointerDownEvent event, DrawingProvider drawing) {
    if (drawing.currentTool == ToolType.lasso && drawing.selection != null) {
      return false;
    }
    final pos = _toCanvasPosition(
      event.position,
      fallbackLocal: event.localPosition,
    );
    _activeDrawPointer = event.pointer;
    _lastOffset = _isInsideCanvas(pos) ? pos : null;
    _pendingDrawStart = _isInsideCanvas(pos) ? pos : null;
    _activeDrawStarted = false;
    if (drawing.currentTool == ToolType.lasso && _isInsideCanvas(pos)) {
      drawing.startLasso(pos);
      _activeDrawStarted = true;
    }
    _syncIgnoreDrawingGestures();
    return true;
  }

  void _handlePointerDown(PointerDownEvent event, DrawingProvider drawing) {
    if (event.kind == ui.PointerDeviceKind.touch) {
      _activeTouchPoints[event.pointer] = event.position;
      if (_isTwoFingerTouchActive) {
        _lastTwoFingerFocalPoint = _twoFingerFocalPoint();
        _lastTwoFingerDistance = _twoFingerDistance();
        _cancelDrawingForTwoFinger(drawing);
        _syncIgnoreDrawingGestures();
        return;
      }
    }

    if (_isSecondaryMouseGesture(event)) {
      _beginSecondaryPan(event, drawing);
      _syncIgnoreDrawingGestures();
      return;
    }

    if (_activeSelectionPointer != null ||
        _activeSecondaryPointer != null ||
        _activeDrawPointer != null ||
        _isTwoFingerTouchActive) {
      return;
    }

    if (_beginSelectionHandleDrag(event, drawing)) {
      _syncIgnoreDrawingGestures();
      return;
    }
    _beginPointerDrawing(event, drawing);
  }

  void _handlePointerMove(PointerMoveEvent event, DrawingProvider drawing) {
    if (_activeSecondaryPointer == event.pointer) {
      if (!_isSecondaryMouseGesture(event)) {
        _activeSecondaryPointer = null;
        _syncIgnoreDrawingGestures();
      }
      return;
    }

    if (_activeSelectionPointer == event.pointer) {
      final pos = _toCanvasPosition(
        event.position,
        fallbackLocal: event.localPosition,
      );
      if (_dragState != null && drawing.selection != null) {
        _updateSelectionTransform(pos, drawing);
      }
      return;
    }

    if (_activeDrawPointer == event.pointer) {
      final pos = _toCanvasPosition(
        event.position,
        fallbackLocal: event.localPosition,
      );
      final bool isInsideCanvas = _isInsideCanvas(pos);
      if (drawing.currentTool == ToolType.lasso) {
        if (!isInsideCanvas) {
          _lastOffset = null;
          return;
        }
        if (!drawing.isDrawingLasso) {
          drawing.startLasso(pos);
          _activeDrawStarted = true;
        } else {
          drawing.extendLasso(pos);
        }
      } else {
        if (!isInsideCanvas) {
          final Offset? lastInside = _lastOffset;
          if (lastInside != null) {
            final Offset? edgePoint = _canvasExitIntersection(lastInside, pos);
            if (edgePoint != null) {
              drawing.addPoint(edgePoint, lastInside);
              _lastOffset = edgePoint;
            }
          }
          if (_activeDrawStarted && !_isShapeTool(drawing.currentTool)) {
            drawing.endLine();
            _activeDrawStarted = false;
          }
          _pendingDrawStart = null;
          _lastOffset = null;
          return;
        }
        if (!_activeDrawStarted) {
          drawing.startNewLine(_pendingDrawStart ?? pos);
          _activeDrawStarted = true;
          _lastOffset = pos;
          _pendingDrawStart = null;
          return;
        }
        if (_lastOffset != null) {
          drawing.addPoint(pos, _lastOffset!);
        }
      }
      _lastOffset = pos;
      return;
    }

    if (!_activeTouchPoints.containsKey(event.pointer)) return;
    _activeTouchPoints[event.pointer] = event.position;
    if (_activeSelectionPointer != null) return;
    if (_isTwoFingerTouchActive) {
      final focal = _twoFingerFocalPoint();
      final distance = _twoFingerDistance();
      if (_lastTwoFingerFocalPoint != null) {
        final delta = focal - _lastTwoFingerFocalPoint!;
        if (delta != Offset.zero) {
          widget.onTwoFingerPan?.call(delta);
        }
      }
      if (_lastTwoFingerDistance != null &&
          _lastTwoFingerDistance! > 0 &&
          distance > 0) {
        final scaleDelta = distance / _lastTwoFingerDistance!;
        if (scaleDelta.isFinite && scaleDelta > 0) {
          widget.onTwoFingerScale?.call(focal, scaleDelta);
        }
      }
      _lastTwoFingerFocalPoint = focal;
      _lastTwoFingerDistance = distance;
      _cancelDrawingForTwoFinger(drawing);
    }
  }

  void _handlePointerUpOrCancel(PointerEvent event, DrawingProvider drawing) {
    if (_activeSecondaryPointer == event.pointer) {
      _activeSecondaryPointer = null;
    }

    if (_activeSelectionPointer == event.pointer) {
      _dragState = null;
      _setSelectionHandleInteraction(false);
    }

    if (_activeDrawPointer == event.pointer) {
      if (drawing.currentTool == ToolType.lasso) {
        if (drawing.isDrawingLasso && _canvasSize != null) {
          drawing.finishLasso(_canvasSize!);
        }
        _dragState = null;
      } else if (_activeDrawStarted) {
        drawing.endLine();
      }
      _activeDrawPointer = null;
      _pendingDrawStart = null;
      _activeDrawStarted = false;
      _lastOffset = null;
    }

    _activeTouchPoints.remove(event.pointer);
    if (_isTwoFingerTouchActive) {
      _lastTwoFingerFocalPoint = _twoFingerFocalPoint();
      _lastTwoFingerDistance = _twoFingerDistance();
    } else {
      _lastTwoFingerFocalPoint = null;
      _lastTwoFingerDistance = null;
    }
    _syncIgnoreDrawingGestures();
  }

  void _handleTapDown(TapDownDetails details) {
    if (_activeSecondaryPointer != null ||
        _activeSelectionPointer != null ||
        _activeDrawPointer != null) {
      _tapDownPosition = null;
      return;
    }
    _tapDownPosition = _toCanvasPosition(
      details.globalPosition,
      fallbackLocal: details.localPosition,
    );
  }

  Future<void> _handleTap(DrawingProvider drawing) async {
    final pos = _tapDownPosition;
    if (pos == null) return;
    _tapDownPosition = null;

    if (drawing.currentTool == ToolType.lasso && drawing.selection != null) {
      final handle = drawing.hitTestSelection(pos);
      if (handle == SelectionHandle.mirror) {
        final now = DateTime.now();
        if (_lastFlipTime == null ||
            now.difference(_lastFlipTime!) > _flipDebounceDuration) {
          drawing.beginSelectionInteraction();
          drawing.flipSelectionHorizontal();
          _lastFlipTime = now;
        }
        return;
      }
      if (handle == SelectionHandle.none &&
          drawing.shouldFinishSelection(pos)) {
        await drawing.commitSelection();
      }
    }
  }

  void _handlePanStart(DragStartDetails details, DrawingProvider drawing) {
    if (_isTwoFingerTouchActive) {
      _lastOffset = null;
      _dragState = null;
      return;
    }
    if (_activeSecondaryPointer != null) {
      _lastOffset = null;
      _dragState = null;
      return;
    }
    if (_activeDrawPointer != null) {
      return;
    }
    if (_activeSelectionPointer != null) {
      _lastOffset = null;
      return;
    }
    final pos = _toCanvasPosition(
      details.globalPosition,
      fallbackLocal: details.localPosition,
    );
    _lastOffset = pos;
    if (drawing.currentTool == ToolType.lasso) {
      if (drawing.selection != null) {
        final handle = drawing.hitTestSelection(
          pos,
          handleRadius: 24,
        );
        if (handle != SelectionHandle.none &&
            handle != SelectionHandle.mirror) {
          drawing.beginSelectionInteraction();
          final sel = drawing.selection!;
          _dragState = SelectionDragState(
            handle: handle,
            startGlobal: pos,
            startLocal: sel.toLocal(pos),
            initialTranslation: sel.translation,
            initialScaleX: sel.scaleX,
            initialScaleY: sel.scaleY,
            initialRotation: sel.rotation,
          );
        } else if (drawing.shouldFinishSelection(pos)) {
          drawing.commitSelection();
        }
        return;
      }
      drawing.startLasso(pos);
      return;
    }
    drawing.startNewLine(pos);
  }

  void _handlePanUpdate(DragUpdateDetails details, DrawingProvider drawing) {
    if (_isTwoFingerTouchActive) return;
    if (_activeSecondaryPointer != null) return;
    if (_activeDrawPointer != null) return;
    if (_activeSelectionPointer != null) return;
    final pos = _toCanvasPosition(
      details.globalPosition,
      fallbackLocal: details.localPosition,
    );
    if (drawing.currentTool == ToolType.lasso) {
      if (drawing.isDrawingLasso) {
        drawing.extendLasso(pos);
        return;
      }
      if (_dragState != null && drawing.selection != null) {
        _updateSelectionTransform(pos, drawing);
      }
      return;
    }
    if (_lastOffset != null) {
      drawing.addPoint(pos, _lastOffset!);
    }
    _lastOffset = pos;
  }

  void _handlePanEnd(DrawingProvider drawing) {
    if (_isTwoFingerTouchActive) {
      _dragState = null;
      _lastOffset = null;
      return;
    }
    if (_activeSecondaryPointer != null) {
      _dragState = null;
      _lastOffset = null;
      return;
    }
    if (_activeDrawPointer != null) {
      return;
    }
    if (_activeSelectionPointer != null) {
      _lastOffset = null;
      return;
    }
    if (drawing.currentTool == ToolType.lasso) {
      if (drawing.isDrawingLasso && _canvasSize != null) {
        drawing.finishLasso(_canvasSize!);
      }
      _dragState = null;
      return;
    }
    drawing.endLine();
    _lastOffset = null;
  }

  Offset _toLocalAtDragStart(
    Offset global,
    SelectionDragState state,
    Rect baseRect,
  ) {
    final Offset shifted = global - state.initialTranslation - baseRect.center;
    final double cosR = math.cos(-state.initialRotation);
    final double sinR = math.sin(-state.initialRotation);
    final Offset rotated = Offset(
      shifted.dx * cosR - shifted.dy * sinR,
      shifted.dx * sinR + shifted.dy * cosR,
    );
    return Offset(
      rotated.dx / state.initialScaleX + baseRect.center.dx,
      rotated.dy / state.initialScaleY + baseRect.center.dy,
    );
  }

  double _stableAngleDelta(Offset startVec, Offset currentVec) {
    // Signed angle between vectors, normalized to [-pi, pi].
    final double cross =
        startVec.dx * currentVec.dy - startVec.dy * currentVec.dx;
    final double dot =
        startVec.dx * currentVec.dx + startVec.dy * currentVec.dy;
    return math.atan2(cross, dot);
  }

  void _updateSelectionTransform(Offset currentPos, DrawingProvider drawing) {
    final state = _dragState;
    final selection = drawing.selection;
    if (state == null || selection == null) return;
    final center = selection.baseRect.center;
    switch (state.handle) {
      case SelectionHandle.inside:
        final delta = currentPos - state.startGlobal;
        drawing.setSelectionTransform(
          translation: state.initialTranslation + delta,
          scaleX: state.initialScaleX,
          scaleY: state.initialScaleY,
          rotation: state.initialRotation,
        );
        break;
      case SelectionHandle.mirror:
        // Do nothing on drag
        break;
      case SelectionHandle.cornerTL:
      case SelectionHandle.cornerTR:
      case SelectionHandle.cornerBR:
      case SelectionHandle.cornerBL:
        final localCurrent =
            _toLocalAtDragStart(currentPos, state, selection.baseRect);
        final startVec = state.startLocal - center;
        final currentVec = localCurrent - center;
        final startLen = startVec.distance;
        final currentLen = currentVec.distance;
        if (startLen > 0.001 && currentLen > 0.001) {
          final double safeStartLen = math.max(startLen, _minHandleDistance);
          final double safeCurrentLen =
              math.max(currentLen, _minHandleDistance);
          final scale = safeCurrentLen / safeStartLen;
          final double baseAngle = _stableAngleDelta(startVec, currentVec);
          final double radiusFactor =
              (math.min(startLen, currentLen) / _rotationSoftRadius)
                  .clamp(0.35, 1.0);
          final double rotationDelta =
              baseAngle * radiusFactor * _rotationSensitivity;
          drawing.setSelectionTransform(
            translation: state.initialTranslation,
            scaleX: state.initialScaleX * scale,
            scaleY: state.initialScaleY * scale,
            rotation: state.initialRotation + rotationDelta,
          );
        }
        break;
      case SelectionHandle.edgeLeft:
      case SelectionHandle.edgeRight:
        final localCurrent =
            _toLocalAtDragStart(currentPos, state, selection.baseRect);
        final startVec = state.startLocal - center;
        final currentVec = localCurrent - center;
        final startAxis = startVec.dx.abs();
        final currentAxis = currentVec.dx.abs();
        if (startAxis > 0.001) {
          final double safeStartAxis = math.max(startAxis, _minHandleDistance);
          final double safeCurrentAxis =
              math.max(currentAxis, _minHandleDistance);
          final scaleX = (safeCurrentAxis / safeStartAxis).clamp(0.05, 20.0);
          drawing.setSelectionTransform(
            translation: state.initialTranslation,
            scaleX: state.initialScaleX * scaleX,
            scaleY: state.initialScaleY,
            rotation: state.initialRotation,
          );
        }
        break;
      case SelectionHandle.edgeTop:
      case SelectionHandle.edgeBottom:
        final localCurrent =
            _toLocalAtDragStart(currentPos, state, selection.baseRect);
        final startVec = state.startLocal - center;
        final currentVec = localCurrent - center;
        final startAxis = startVec.dy.abs();
        final currentAxis = currentVec.dy.abs();
        if (startAxis > 0.001) {
          final double safeStartAxis = math.max(startAxis, _minHandleDistance);
          final double safeCurrentAxis =
              math.max(currentAxis, _minHandleDistance);
          final scaleY = (safeCurrentAxis / safeStartAxis).clamp(0.05, 20.0);
          drawing.setSelectionTransform(
            translation: state.initialTranslation,
            scaleX: state.initialScaleX,
            scaleY: state.initialScaleY * scaleY,
            rotation: state.initialRotation,
          );
        }
        break;
      case SelectionHandle.none:
        break;
    }
  }
}

class SelectionDragState {
  final SelectionHandle handle;
  final Offset startGlobal;
  final Offset startLocal;
  final Offset initialTranslation;
  final double initialScaleX;
  final double initialScaleY;
  final double initialRotation;
  SelectionDragState({
    required this.handle,
    required this.startGlobal,
    required this.startLocal,
    required this.initialTranslation,
    required this.initialScaleX,
    required this.initialScaleY,
    required this.initialRotation,
  });
}

class DrawingPainter extends CustomPainter {
  final List<DrawnLine> layerALines;
  final List<DrawnLine> layerBLines;
  final List<DrawnLine> layerCLines;
  final bool isLayerAVisible;
  final bool isLayerBVisible;
  final bool isLayerCVisible;
  final double layerAOpacity;
  final double layerBOpacity;
  final double layerCOpacity;
  final ui.Image? layerABaseImage;
  final ui.Image? layerBBaseImage;
  final ui.Image? layerCBaseImage;
  final RasterSamplingMode layerABaseSampling;
  final RasterSamplingMode layerBBaseSampling;
  final RasterSamplingMode layerCBaseSampling;
  final ui.ImageShader? tone30Shader;
  final ui.ImageShader? tone60Shader;
  final ui.ImageShader? tone80Shader;
  final List<LayerPlacement> placements;
  final LassoSelection? selection;
  final bool selectionMasksSource;
  final bool selectionHandlesFilled;
  final List<Offset> lassoDraft;
  final bool isDrawingLasso;
  final Map<SelectionHandle, Offset> handles;
  final ToolType currentTool;
  final Offset? shapeStart;
  final Offset? shapeEnd;
  final Size canvasSize;
  final Offset canvasVisualOffset;

  DrawingPainter({
    required this.layerALines,
    required this.layerBLines,
    required this.layerCLines,
    required this.isLayerAVisible,
    required this.isLayerBVisible,
    required this.isLayerCVisible,
    required this.layerAOpacity,
    required this.layerBOpacity,
    required this.layerCOpacity,
    required this.layerABaseImage,
    required this.layerBBaseImage,
    required this.layerCBaseImage,
    required this.layerABaseSampling,
    required this.layerBBaseSampling,
    required this.layerCBaseSampling,
    required this.tone30Shader,
    required this.tone60Shader,
    required this.tone80Shader,
    required this.placements,
    required this.selection,
    required this.selectionMasksSource,
    required this.selectionHandlesFilled,
    required this.lassoDraft,
    required this.isDrawingLasso,
    required this.handles,
    required this.currentTool,
    required this.shapeStart,
    required this.shapeEnd,
    required this.canvasSize,
    required this.canvasVisualOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ★ ここを削除（またはコメントアウト） ★
    // canvas.drawColor(Colors.white, BlendMode.srcOver);

    canvas.save();
    canvas.translate(canvasVisualOffset.dx, canvasVisualOffset.dy);

    final Path? layerAHolePath = selectionMasksSource &&
            selection != null &&
            selection!.layer == DrawingLayer.layerA
        ? selection!.maskPath
        : null;
    final Path? layerBHolePath = selectionMasksSource &&
            selection != null &&
            selection!.layer == DrawingLayer.layerB
        ? selection!.maskPath
        : null;
    final Path? layerCHolePath = selectionMasksSource &&
            selection != null &&
            selection!.layer == DrawingLayer.layerC
        ? selection!.maskPath
        : null;

    _drawLayer(
      canvas,
      canvasSize,
      DrawingLayer.layerA,
      null,
      isVisible: isLayerAVisible,
      opacity: layerAOpacity,
      holePath: layerAHolePath,
    );
    _drawLayer(
      canvas,
      canvasSize,
      DrawingLayer.layerB,
      null,
      isVisible: isLayerBVisible,
      opacity: layerBOpacity,
      holePath: layerBHolePath,
    );
    _drawLayer(
      canvas,
      canvasSize,
      DrawingLayer.layerC,
      null,
      isVisible: isLayerCVisible,
      opacity: layerCOpacity,
      holePath: layerCHolePath,
    );

    if (selection != null) {
      final bool selectionVisible = switch (selection!.layer) {
        DrawingLayer.layerA => isLayerAVisible,
        DrawingLayer.layerB => isLayerBVisible,
        DrawingLayer.layerC => isLayerCVisible,
      };
      final double selectionOpacity = switch (selection!.layer) {
        DrawingLayer.layerA => layerAOpacity,
        DrawingLayer.layerB => layerBOpacity,
        DrawingLayer.layerC => layerCOpacity,
      };
      if (selectionVisible && selectionOpacity > 0) {
        canvas.saveLayer(
          Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
          Paint()..color = Colors.white.withValues(alpha: selectionOpacity),
        );
        _paintSelection(
          canvas,
          selection!,
        );
        canvas.restore();
        _paintSelectionOverlay(canvas, selection!, handles);
      }
    }
    if (isDrawingLasso && lassoDraft.length > 1) {
      _drawLassoDraft(canvas);
    }
    if (_isShapeTool(currentTool) && shapeStart != null && shapeEnd != null) {
      _drawShapeGuide(canvas, currentTool, shapeStart!, shapeEnd!);
    }
    canvas.restore();
  }

  void _drawLayer(
    Canvas canvas,
    Size size,
    DrawingLayer layer,
    ui.Image? baseImage, {
    required bool isVisible,
    required double opacity,
    Path? holePath,
  }) {
    if (!isVisible || opacity <= 0) return;
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );
    if (baseImage != null) {
      // FilterQuality.low で輪郭を維持し、元画像をグレースケール化せずそのまま表示（矩形描画時も同様）
      canvas.drawImage(
        baseImage,
        Offset.zero,
        Paint()
          ..isAntiAlias = false
          ..filterQuality = FilterQuality.none,
      );
    }
    _paintCommittedPlacementsForLayer(canvas, layer);
    if (holePath != null) {
      canvas.drawPath(
        holePath,
        Paint()
          ..blendMode = BlendMode.clear
          ..isAntiAlias = false,
      );
    }
    canvas.restore();
  }

  List<DrawnLine> _allLinesSortedBySequence() {
    final List<DrawnLine> all = <DrawnLine>[
      ...layerALines,
      ...layerBLines,
      ...layerCLines,
    ]..sort((DrawnLine a, DrawnLine b) => a.sequence.compareTo(b.sequence));
    return all;
  }

  void _paintCommittedPlacementsForLayer(Canvas canvas, DrawingLayer layer) {
    LayerCompositePainter.paintSourceContentsUpTo(
      canvas,
      layer,
      kLayerCompositeMaxSequence,
      allLines: _allLinesSortedBySequence(),
      allPlacements: placements,
      layerABaseImage: layerABaseImage,
      layerBBaseImage: layerBBaseImage,
      layerCBaseImage: layerCBaseImage,
      layerABaseSampling: layerABaseSampling,
      layerBBaseSampling: layerBBaseSampling,
      layerCBaseSampling: layerCBaseSampling,
      tone30Shader: tone30Shader,
      tone60Shader: tone60Shader,
      tone80Shader: tone80Shader,
    );
  }

  void _paintSelection(
    Canvas canvas,
    LassoSelection selection,
  ) {
    LayerCompositePainter.paintLassoSelection(
      canvas,
      selection,
      allLines: _allLinesSortedBySequence(),
      allPlacements: placements,
      layerABaseImage: layerABaseImage,
      layerBBaseImage: layerBBaseImage,
      layerCBaseImage: layerCBaseImage,
      layerABaseSampling: layerABaseSampling,
      layerBBaseSampling: layerBBaseSampling,
      layerCBaseSampling: layerCBaseSampling,
      tone30Shader: tone30Shader,
      tone60Shader: tone60Shader,
      tone80Shader: tone80Shader,
    );
  }

  void _paintSelectionOverlay(
    Canvas canvas,
    LassoSelection selection,
    Map<SelectionHandle, Offset> handles,
  ) {
    final corners = selection.transformedCorners();
    final paint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Draw dashed outline
    const double dashLength = 8;
    const double gapLength = 5;
    for (int i = 0; i < corners.length; i++) {
      final Offset start = corners[i];
      final Offset end = corners[(i + 1) % corners.length];
      final double totalLength = (end - start).distance;
      final int dashCount = (totalLength / (dashLength + gapLength)).floor();
      final Offset direction = (end - start) / totalLength;
      for (int d = 0; d < dashCount; d++) {
        final double dashStart = d * (dashLength + gapLength);
        final Offset from = start + direction * dashStart;
        final Offset to = from + direction * dashLength;
        canvas.drawLine(from, to, paint);
      }
    }

    // Handles
    const double handleSize = 12;
    final handleFillPaint = Paint()
      ..color = selectionHandlesFilled ? Colors.black : Colors.white
      ..style = PaintingStyle.fill;
    final handleStrokePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final entry in handles.entries) {
      if (entry.key == SelectionHandle.mirror) continue;
      final rect = Rect.fromCenter(
        center: entry.value,
        width: handleSize,
        height: handleSize,
      );
      canvas.drawRect(rect, handleFillPaint);
      canvas.drawRect(rect, handleStrokePaint);
    }

    // Mirror button: draw ◀▷ text in system font inside a small rounded rect
    if (handles.containsKey(SelectionHandle.mirror)) {
      final pos = handles[SelectionHandle.mirror]!;
      final rect = Rect.fromCenter(center: pos, width: 48, height: 40);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      final bg = Paint()..color = Colors.white;
      canvas.drawRRect(rrect, bg);
      canvas.drawRRect(rrect, paint);
      final textPainter = TextPainter(
        text: const TextSpan(
          text: '◀▷',
          style: TextStyle(fontSize: 20, color: Colors.black),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        rect.center - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  void _drawLassoDraft(Canvas canvas) {
    final paint = Paint()
      ..color = Colors.blueGrey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()..addPolygon(lassoDraft, false);
    canvas.drawPath(path, paint);
  }

  bool _isShapeTool(ToolType tool) {
    return tool == ToolType.rect ||
        tool == ToolType.fillRect ||
        tool == ToolType.circle ||
        tool == ToolType.fillCircle ||
        tool == ToolType.line;
  }

  void _drawShapeGuide(Canvas canvas, ToolType tool, Offset start, Offset end) {
    final rect = Rect.fromPoints(start, end);
    final path = Path();
    switch (tool) {
      case ToolType.rect:
      case ToolType.fillRect:
        path.addRect(rect);
        break;
      case ToolType.circle:
      case ToolType.fillCircle:
        path.addOval(rect);
        break;
      case ToolType.line:
        path
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy);
        break;
      default:
        return;
    }
    final paint = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    _drawDashedPath(canvas, path, paint);
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint,
      {double dashLength = 8, double gapLength = 6}) {
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      final length = metric.length;
      while (distance < length) {
        final double next = distance + dashLength;
        final segment = metric.extractPath(distance, next.clamp(0, length));
        canvas.drawPath(segment, paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/drawing.dart';
import '../painting/layer_composite_painter.dart';
import '../painting/pixel_geometry.dart';
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
  ui.PointerDeviceKind? _activeDrawPointerKind;
  int? _activeSecondaryPointer;
  Offset? _pendingDrawStart;
  bool _activeDrawStarted = false;
  final Set<int> _suppressedTouchPointers = <int>{};
  Timer? _strokeResumeTimer;
  DateTime? _strokeResumeDeadline;
  Offset? _strokeResumeAnchor;
  ToolType? _strokeResumeTool;
  DateTime? _lastFlipTime;
  Offset? _tapDownPosition;
  Offset? _lastLassoOutsidePosition;
  bool _isTrackingLassoOutsideCanvas = false;
  static const Duration _flipDebounceDuration = Duration(milliseconds: 500);
  static const Duration _strokeResumeGraceDuration =
      Duration(milliseconds: 700);
  static const double _strokeResumeDistanceThreshold = 42.0;
  static const double _palmRadiusThreshold = 24.0;
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
                  child: _CanvasPaintStack(
                    drawing: drawing,
                    logicalSize: logicalSize,
                    canvasVisualOffset: widget.canvasVisualOffset,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _strokeResumeTimer?.cancel();
    super.dispose();
  }

  bool get _isTwoFingerTouchActive => _activeTouchPoints.length >= 2;
  bool get _hasPendingStrokeResume => _strokeResumeDeadline != null;

  bool _supportsStrokeResume(ToolType tool) {
    return tool == ToolType.pen ||
        tool == ToolType.tone30 ||
        tool == ToolType.tone60 ||
        tool == ToolType.tone80;
  }

  bool _usesPalmRejection(DrawingProvider drawing) {
    return drawing.currentTool == ToolType.pen ||
        drawing.currentTool == ToolType.pressure ||
        drawing.currentTool == ToolType.eraser ||
        drawing.currentTool == ToolType.tone30 ||
        drawing.currentTool == ToolType.tone60 ||
        drawing.currentTool == ToolType.tone80;
  }

  bool _isLikelyPalmTouch(PointerEvent event) {
    if (event.kind != ui.PointerDeviceKind.touch) return false;
    final double major = event.radiusMajor;
    final double minor = event.radiusMinor;
    if (major >= _palmRadiusThreshold || minor >= _palmRadiusThreshold) {
      return true;
    }
    return major > 0 &&
        minor > 0 &&
        (major * minor) >= (_palmRadiusThreshold * 14.0);
  }

  void _clearStrokeResumeState() {
    _strokeResumeTimer?.cancel();
    _strokeResumeTimer = null;
    _strokeResumeDeadline = null;
    _strokeResumeAnchor = null;
    _strokeResumeTool = null;
  }

  void _resetLassoBoundaryTracking() {
    _lastLassoOutsidePosition = null;
    _isTrackingLassoOutsideCanvas = false;
  }

  void _finalizePendingStrokeResume(DrawingProvider drawing) {
    if (!_hasPendingStrokeResume || _activeDrawPointer != null) return;
    _clearStrokeResumeState();
    if (_activeDrawStarted) {
      drawing.endLine();
    }
    _activeDrawStarted = false;
    _lastOffset = null;
    _pendingDrawStart = null;
    _activeDrawPointerKind = null;
    _syncIgnoreDrawingGestures();
  }

  void _scheduleStrokeResume(PointerEvent event, DrawingProvider drawing) {
    _clearStrokeResumeState();
    _strokeResumeDeadline = DateTime.now().add(_strokeResumeGraceDuration);
    _strokeResumeAnchor = _lastOffset ??
        _toCanvasPosition(
          event.position,
          fallbackLocal: event.localPosition,
        );
    _strokeResumeTool = drawing.currentTool;
    _activeDrawPointerKind = event.kind;
    _strokeResumeTimer = Timer(_strokeResumeGraceDuration, () {
      if (!mounted) return;
      _finalizePendingStrokeResume(drawing);
    });
    _syncIgnoreDrawingGestures();
  }

  bool _isResumeCandidate(PointerDownEvent event, DrawingProvider drawing) {
    if (!_hasPendingStrokeResume ||
        !_supportsStrokeResume(drawing.currentTool) ||
        _strokeResumeTool != drawing.currentTool) {
      return false;
    }
    final DateTime? deadline = _strokeResumeDeadline;
    if (deadline == null || DateTime.now().isAfter(deadline)) {
      return false;
    }
    final Offset pos = _toCanvasPosition(
      event.position,
      fallbackLocal: event.localPosition,
    );
    final Offset? anchor = _strokeResumeAnchor;
    return anchor != null &&
        _isInsideCanvas(pos) &&
        (pos - anchor).distance <= _strokeResumeDistanceThreshold;
  }

  bool _tryResumeStroke(PointerDownEvent event, DrawingProvider drawing) {
    if (!_isResumeCandidate(event, drawing)) {
      if (_hasPendingStrokeResume &&
          (!_supportsStrokeResume(drawing.currentTool) ||
              _strokeResumeTool != drawing.currentTool)) {
        _finalizePendingStrokeResume(drawing);
      }
      return false;
    }
    final pos = _toCanvasPosition(
      event.position,
      fallbackLocal: event.localPosition,
    );

    _clearStrokeResumeState();
    _activeDrawPointer = event.pointer;
    _activeDrawPointerKind = event.kind;
    _activeDrawStarted = true;
    _pendingDrawStart = null;
    if (_lastOffset != null && (pos - _lastOffset!).distance >= 0.5) {
      drawing.addPoint(pos, _lastOffset!);
    }
    _lastOffset = pos;
    _syncIgnoreDrawingGestures();
    return true;
  }

  bool _shouldSuppressTouchPointer(
    PointerDownEvent event,
    DrawingProvider drawing,
  ) {
    if (!_usesPalmRejection(drawing) ||
        event.kind != ui.PointerDeviceKind.touch) {
      return false;
    }
    if (_isLikelyPalmTouch(event)) {
      return true;
    }
    if (_isResumeCandidate(event, drawing)) {
      return false;
    }
    return _activeDrawPointerKind == ui.PointerDeviceKind.stylus ||
        _activeDrawPointerKind == ui.PointerDeviceKind.invertedStylus;
  }

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

  Offset _twoFingerCanvasFocalPoint() {
    final points = _activeTouchPoints.values
        .take(2)
        .map(_toCanvasPosition)
        .toList(growable: false);
    return Offset(
      (points[0].dx + points[1].dx) / 2,
      (points[0].dy + points[1].dy) / 2,
    );
  }

  double _twoFingerCanvasDistance() {
    final points = _activeTouchPoints.values
        .take(2)
        .map(_toCanvasPosition)
        .toList(growable: false);
    return (points[0] - points[1]).distance;
  }

  bool _isRadialPreviewInteractive(DrawingProvider drawing) {
    return drawing.currentTool == ToolType.radial && drawing.hasRadialPreview;
  }

  void _cancelDrawingForTwoFinger(DrawingProvider drawing) {
    _clearStrokeResumeState();
    _resetLassoBoundaryTracking();
    _dragState = null;
    _lastOffset = null;
    _activeDrawPointer = null;
    _activeDrawPointerKind = null;
    _pendingDrawStart = null;
    _activeDrawStarted = false;
    if (_isRadialPreviewInteractive(drawing)) {
      return;
    }
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
      return pixelOffset(mapper(globalPosition));
    }
    return pixelOffset(fallbackLocal ?? globalPosition);
  }

  // キャンバス端の描画を許可するため、微小な余裕（epsilon）を持たせる
  static const double _canvasEdgeEpsilon = 0.001;

  bool _isInsideCanvas(Offset position) {
    final Size size = _canvasSize ?? widget.logicalCanvasSize ?? Size.zero;
    if (size == Size.zero) return false;
    return position.dx >= -_canvasEdgeEpsilon &&
        position.dy >= -_canvasEdgeEpsilon &&
        position.dx <= size.width + _canvasEdgeEpsilon &&
        position.dy <= size.height + _canvasEdgeEpsilon;
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
    return pixelOffset(Offset(
      inside.dx + dx * t,
      inside.dy + dy * t,
    ));
  }

  Offset _projectPointToCanvasBounds(Offset position) {
    final Size size = _canvasSize ?? widget.logicalCanvasSize ?? Size.zero;
    if (size == Size.zero) return position;
    return pixelOffset(Offset(
      position.dx.clamp(0.0, size.width).toDouble(),
      position.dy.clamp(0.0, size.height).toDouble(),
    ));
  }

  void _appendLassoPointIfNeeded(DrawingProvider drawing, Offset point) {
    final Offset? lastPoint = _lastOffset;
    if (lastPoint != null && (point - lastPoint).distance < 0.5) {
      return;
    }
    if (!drawing.isDrawingLasso) {
      drawing.startLasso(point);
      _activeDrawStarted = true;
    } else {
      drawing.extendLasso(point);
    }
    _lastOffset = point;
  }

  void _trackLassoPointer(Offset position, DrawingProvider drawing) {
    final bool isInsideCanvas = _isInsideCanvas(position);
    if (isInsideCanvas) {
      if (_isTrackingLassoOutsideCanvas && _lastLassoOutsidePosition != null) {
        final Offset entryPoint =
            _canvasExitIntersection(position, _lastLassoOutsidePosition!) ??
                _projectPointToCanvasBounds(_lastLassoOutsidePosition!);
        _appendLassoPointIfNeeded(drawing, entryPoint);
      }
      _appendLassoPointIfNeeded(drawing, position);
      _resetLassoBoundaryTracking();
      return;
    }
    if (!drawing.isDrawingLasso && !_activeDrawStarted) {
      return;
    }
    final Offset boundaryPoint;
    if (_isTrackingLassoOutsideCanvas) {
      boundaryPoint = _projectPointToCanvasBounds(position);
    } else if (_lastOffset != null) {
      boundaryPoint = _canvasExitIntersection(_lastOffset!, position) ??
          _projectPointToCanvasBounds(position);
    } else {
      boundaryPoint = _projectPointToCanvasBounds(position);
    }
    _appendLassoPointIfNeeded(drawing, boundaryPoint);
    _isTrackingLassoOutsideCanvas = true;
    _lastLassoOutsidePosition = position;
  }

  void _syncIgnoreDrawingGestures() {
    final bool shouldIgnore = _isTwoFingerTouchActive ||
        _activeSecondaryPointer != null ||
        _activeSelectionPointer != null;
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
    if (_tryResumeStroke(event, drawing)) {
      return true;
    }
    final pos = _toCanvasPosition(
      event.position,
      fallbackLocal: event.localPosition,
    );
    _clearStrokeResumeState();
    _activeDrawPointer = event.pointer;
    _activeDrawPointerKind = event.kind;
    _lastOffset = _isInsideCanvas(pos) ? pos : null;
    _pendingDrawStart = _isInsideCanvas(pos) ? pos : null;
    _activeDrawStarted = false;
    if (drawing.currentTool == ToolType.radial) {
      if (!_isInsideCanvas(pos)) {
        _activeDrawPointer = null;
        _activeDrawPointerKind = null;
        _lastOffset = null;
        _pendingDrawStart = null;
        return false;
      }
      if (!drawing.hasRadialPreview) {
        drawing.startRadialPreview(pos);
      }
      _activeDrawStarted = true;
      _pendingDrawStart = null;
      _syncIgnoreDrawingGestures();
      return true;
    }
    if (drawing.currentTool == ToolType.lasso && _isInsideCanvas(pos)) {
      _resetLassoBoundaryTracking();
      drawing.startLasso(pos);
      _activeDrawStarted = true;
    }
    _syncIgnoreDrawingGestures();
    return true;
  }

  void _handlePointerDown(PointerDownEvent event, DrawingProvider drawing) {
    if (_suppressedTouchPointers.contains(event.pointer)) {
      return;
    }

    if (_hasPendingStrokeResume &&
        _activeDrawPointer == null &&
        !_isResumeCandidate(event, drawing)) {
      _finalizePendingStrokeResume(drawing);
    }

    if (_shouldSuppressTouchPointer(event, drawing)) {
      _suppressedTouchPointers.add(event.pointer);
      return;
    }

    final bool resumeTouchCandidate =
        event.kind == ui.PointerDeviceKind.touch &&
            _isResumeCandidate(event, drawing);

    if (resumeTouchCandidate) {
      _activeTouchPoints
        ..clear()
        ..[event.pointer] = event.position;
      _lastTwoFingerFocalPoint = null;
      _lastTwoFingerDistance = null;
    } else if (event.kind == ui.PointerDeviceKind.touch) {
      _activeTouchPoints[event.pointer] = event.position;
      if (_isTwoFingerTouchActive) {
        if (_isRadialPreviewInteractive(drawing)) {
          _lastTwoFingerFocalPoint = _twoFingerCanvasFocalPoint();
          _lastTwoFingerDistance = _twoFingerCanvasDistance();
        } else {
          _lastTwoFingerFocalPoint = _twoFingerFocalPoint();
          _lastTwoFingerDistance = _twoFingerDistance();
        }
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
    if (_suppressedTouchPointers.contains(event.pointer)) {
      return;
    }

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
        _trackLassoPointer(pos, drawing);
      } else if (drawing.currentTool == ToolType.radial) {
        final Offset? center = drawing.radialPreviewCenter;
        final Offset? lastOffset = _lastOffset;
        if (center == null || lastOffset == null) {
          _lastOffset = pos;
          return;
        }
        final Offset delta = pos - lastOffset;
        if (delta != Offset.zero) {
          drawing.transformRadialPreview(center: center + delta);
        }
      } else {
        if (!isInsideCanvas) {
          final Offset? lastInside = _lastOffset;
          if (lastInside != null) {
            final Offset? edgePoint = _canvasExitIntersection(lastInside, pos);
            if (edgePoint != null) {
              if (!_activeDrawStarted) {
                drawing.startNewLine(_pendingDrawStart ?? lastInside);
                _activeDrawStarted = true;
              }
              drawing.addPoint(
                edgePoint,
                lastInside,
                preserveExactPoint: true,
              );
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
      if (_isRadialPreviewInteractive(drawing)) {
        final Offset focal = _twoFingerCanvasFocalPoint();
        final double distance = _twoFingerCanvasDistance();
        Offset? nextCenter;
        double? nextRadius;
        if (_lastTwoFingerFocalPoint != null &&
            drawing.radialPreviewCenter != null) {
          nextCenter = drawing.radialPreviewCenter! +
              (focal - _lastTwoFingerFocalPoint!);
        }
        if (_lastTwoFingerDistance != null &&
            _lastTwoFingerDistance! > 0 &&
            distance > 0) {
          final double scaleDelta = distance / _lastTwoFingerDistance!;
          if (scaleDelta.isFinite && scaleDelta > 0) {
            nextRadius = drawing.radialPreviewRadius * scaleDelta;
          }
        }
        drawing.transformRadialPreview(
          center: nextCenter,
          radius: nextRadius,
        );
        _lastTwoFingerFocalPoint = focal;
        _lastTwoFingerDistance = distance;
        return;
      }

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
    if (_suppressedTouchPointers.remove(event.pointer)) {
      _activeTouchPoints.remove(event.pointer);
      return;
    }

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
        _resetLassoBoundaryTracking();
        _dragState = null;
        _activeDrawStarted = false;
        _lastOffset = null;
        _clearStrokeResumeState();
        _activeDrawPointerKind = null;
      } else if (drawing.currentTool == ToolType.radial) {
        _activeDrawStarted = false;
        _lastOffset = null;
        _clearStrokeResumeState();
        _activeDrawPointerKind = null;
      } else if (_activeDrawStarted) {
        if (event is! PointerCancelEvent &&
            _supportsStrokeResume(drawing.currentTool)) {
          _scheduleStrokeResume(event, drawing);
        } else {
          drawing.endLine();
          _activeDrawStarted = false;
          _lastOffset = null;
          _activeDrawPointerKind = null;
        }
      } else {
        _activeDrawPointerKind = null;
      }
      _activeDrawPointer = null;
      _pendingDrawStart = null;
    }

    _activeTouchPoints.remove(event.pointer);
    if (_isTwoFingerTouchActive) {
      if (_isRadialPreviewInteractive(drawing)) {
        _lastTwoFingerFocalPoint = _twoFingerCanvasFocalPoint();
        _lastTwoFingerDistance = _twoFingerCanvasDistance();
      } else {
        _lastTwoFingerFocalPoint = _twoFingerFocalPoint();
        _lastTwoFingerDistance = _twoFingerDistance();
      }
    } else {
      _lastTwoFingerFocalPoint = null;
      _lastTwoFingerDistance = null;
    }
    _syncIgnoreDrawingGestures();
  }

  void _handleTapDown(TapDownDetails details) {
    if (_activeSecondaryPointer != null ||
        _activeSelectionPointer != null ||
        _activeDrawPointer != null ||
        _hasPendingStrokeResume) {
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
      if (drawing.isSelectionMirrorButtonHit(pos)) {
        final now = DateTime.now();
        if (_lastFlipTime == null ||
            now.difference(_lastFlipTime!) > _flipDebounceDuration) {
          drawing.beginSelectionInteraction();
          drawing.flipSelectionHorizontal();
          _lastFlipTime = now;
        }
        return;
      }
      if (drawing.hitTestSelection(pos) == SelectionHandle.none &&
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
    if (_hasPendingStrokeResume) {
      _lastOffset = null;
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
        if (drawing.isSelectionMirrorButtonHit(pos)) {
          return;
        }
        final handle = drawing.hitTestSelection(
          pos,
          handleRadius: 24,
        );
        if (handle != SelectionHandle.none) {
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
      _resetLassoBoundaryTracking();
      _lastOffset = pos;
      drawing.startLasso(pos);
      return;
    }
    drawing.startNewLine(pos);
  }

  void _handlePanUpdate(DragUpdateDetails details, DrawingProvider drawing) {
    if (_isTwoFingerTouchActive) return;
    if (_activeSecondaryPointer != null) return;
    if (_activeDrawPointer != null) return;
    if (_hasPendingStrokeResume) return;
    if (_activeSelectionPointer != null) return;
    final pos = _toCanvasPosition(
      details.globalPosition,
      fallbackLocal: details.localPosition,
    );
    if (drawing.currentTool == ToolType.lasso) {
      if (drawing.isDrawingLasso) {
        _trackLassoPointer(pos, drawing);
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
    if (_hasPendingStrokeResume) {
      _dragState = null;
      _lastOffset = null;
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
      _resetLassoBoundaryTracking();
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
      case SelectionHandle.rotate:
        final Offset rotationCenter =
            selection.baseRect.center + state.initialTranslation;
        final Offset startVector = state.startGlobal - rotationCenter;
        final Offset currentVector = currentPos - rotationCenter;
        if (startVector.distance > 0.001 && currentVector.distance > 0.001) {
          drawing.setSelectionTransform(
            translation: state.initialTranslation,
            scaleX: state.initialScaleX,
            scaleY: state.initialScaleY,
            rotation: state.initialRotation +
                _stableAngleDelta(startVector, currentVector),
          );
        }
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

class _CanvasPaintStack extends StatelessWidget {
  final DrawingProvider drawing;
  final Size logicalSize;
  final Offset canvasVisualOffset;

  const _CanvasPaintStack({
    required this.drawing,
    required this.logicalSize,
    required this.canvasVisualOffset,
  });

  bool get _canUseSplitRendering {
    if (drawing.selection != null || drawing.placements.isNotEmpty) {
      return false;
    }
    if (drawing.layerABaseImage != null ||
        drawing.layerBBaseImage != null ||
        drawing.layerCBaseImage != null) {
      return false;
    }
    for (final DrawnLine line in drawing.lines) {
      if (line.isEraser) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_canUseSplitRendering) {
      return SizedBox.expand(
        child: CustomPaint(
          painter: DrawingPainter(
            allLines: drawing.lines,
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
            currentStrokeWidth: drawing.strokeWidth,
            shapeStart: drawing.shapeStart,
            shapeEnd: drawing.shapeEnd,
            linesStartPointRatioA: drawing.linesStartPointRatioA,
            linesStartPointRatioB: drawing.linesStartPointRatioB,
            radialPreviewCenter: drawing.radialPreviewCenter,
            radialPreviewStartAngle: drawing.radialPreviewStartAngle,
            radialPreviewSweepAngle: drawing.radialPreviewSweepAngle,
            radialPreviewRadius: drawing.radialPreviewRadius,
            radialLineCountA: drawing.radialLineCountA,
            radialLineCountB: drawing.radialLineCountB,
            radialOffsetAngleA: drawing.radialOffsetAngleA,
            radialOffsetAngleB: drawing.radialOffsetAngleB,
            canvasRevision: drawing.canvasRevision,
            layerContentRevision: drawing.layerContentRevision,
            canvasSize: logicalSize,
            canvasVisualOffset: canvasVisualOffset,
          ),
        ),
      );
    }

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: StaticLayerPainter(
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
                canvasSize: logicalSize,
                canvasVisualOffset: canvasVisualOffset,
              ),
            ),
          ),
          RepaintBoundary(
            child: CustomPaint(
              painter: DynamicLayerPainter(
                allLines: drawing.lines,
                isLayerAVisible: drawing.isLayerAVisible,
                isLayerBVisible: drawing.isLayerBVisible,
                isLayerCVisible: drawing.isLayerCVisible,
                layerAOpacity: drawing.layerAOpacity,
                layerBOpacity: drawing.layerBOpacity,
                layerCOpacity: drawing.layerCOpacity,
                tone30Shader: drawing.tone30Shader,
                tone60Shader: drawing.tone60Shader,
                tone80Shader: drawing.tone80Shader,
                canvasRevision: drawing.canvasRevision,
                canvasSize: logicalSize,
                canvasVisualOffset: canvasVisualOffset,
              ),
            ),
          ),
          IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: CanvasOverlayPainter(
                  lassoDraft: drawing.lassoDraft,
                  isDrawingLasso: drawing.isDrawingLasso,
                  currentTool: drawing.currentTool,
                  currentStrokeWidth: drawing.strokeWidth,
                  shapeStart: drawing.shapeStart,
                  shapeEnd: drawing.shapeEnd,
                  linesStartPointRatioA: drawing.linesStartPointRatioA,
                  linesStartPointRatioB: drawing.linesStartPointRatioB,
                  radialPreviewCenter: drawing.radialPreviewCenter,
                  radialPreviewStartAngle: drawing.radialPreviewStartAngle,
                  radialPreviewSweepAngle: drawing.radialPreviewSweepAngle,
                  radialPreviewRadius: drawing.radialPreviewRadius,
                  radialLineCountA: drawing.radialLineCountA,
                  radialLineCountB: drawing.radialLineCountB,
                  radialOffsetAngleA: drawing.radialOffsetAngleA,
                  radialOffsetAngleB: drawing.radialOffsetAngleB,
                  canvasRevision: drawing.canvasRevision,
                  canvasSize: logicalSize,
                  canvasVisualOffset: canvasVisualOffset,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RadialPreviewSegment {
  final Offset start;
  final Offset end;
  final int groupIndex;

  const _RadialPreviewSegment({
    required this.start,
    required this.end,
    required this.groupIndex,
  });
}

class StaticLayerPainter extends CustomPainter {
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
  final Size canvasSize;
  final Offset canvasVisualOffset;

  StaticLayerPainter({
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
    required this.canvasSize,
    required this.canvasVisualOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final Offset snappedVisualOffset = pixelOffset(canvasVisualOffset);
    canvas.translate(snappedVisualOffset.dx, snappedVisualOffset.dy);
    _paintLayer(
      canvas,
      layerABaseImage,
      isVisible: isLayerAVisible,
      opacity: layerAOpacity,
      sampling: layerABaseSampling,
    );
    _paintLayer(
      canvas,
      layerBBaseImage,
      isVisible: isLayerBVisible,
      opacity: layerBOpacity,
      sampling: layerBBaseSampling,
    );
    _paintLayer(
      canvas,
      layerCBaseImage,
      isVisible: isLayerCVisible,
      opacity: layerCOpacity,
      sampling: layerCBaseSampling,
    );
    canvas.restore();
  }

  void _paintLayer(
    Canvas canvas,
    ui.Image? image, {
    required bool isVisible,
    required double opacity,
    required RasterSamplingMode sampling,
  }) {
    if (!isVisible || opacity <= 0.0 || image == null) {
      return;
    }
    if (opacity < 1.0) {
      canvas.saveLayer(
        pixelRectFromLTWH(0, 0, canvasSize.width, canvasSize.height),
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
    }
    final Paint paint = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;
    final Rect dstRect =
        pixelRectFromLTWH(0, 0, canvasSize.width, canvasSize.height);
    final bool keepsNativePixels =
        dstRect.width.round() == image.width &&
            dstRect.height.round() == image.height;
    if (keepsNativePixels) {
      canvas.drawImage(image, pixelOffset(dstRect.topLeft), paint);
    } else {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(
          0,
          0,
          image.width.toDouble(),
          image.height.toDouble(),
        ),
        dstRect,
        paint,
      );
    }
    if (opacity < 1.0) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant StaticLayerPainter oldDelegate) {
    return isLayerAVisible != oldDelegate.isLayerAVisible ||
        isLayerBVisible != oldDelegate.isLayerBVisible ||
        isLayerCVisible != oldDelegate.isLayerCVisible ||
        layerAOpacity != oldDelegate.layerAOpacity ||
        layerBOpacity != oldDelegate.layerBOpacity ||
        layerCOpacity != oldDelegate.layerCOpacity ||
        layerABaseImage != oldDelegate.layerABaseImage ||
        layerBBaseImage != oldDelegate.layerBBaseImage ||
        layerCBaseImage != oldDelegate.layerCBaseImage ||
        layerABaseSampling != oldDelegate.layerABaseSampling ||
        layerBBaseSampling != oldDelegate.layerBBaseSampling ||
        layerCBaseSampling != oldDelegate.layerCBaseSampling ||
        canvasSize != oldDelegate.canvasSize ||
        canvasVisualOffset != oldDelegate.canvasVisualOffset;
  }
}

class DynamicLayerPainter extends CustomPainter {
  final List<DrawnLine> allLines;
  final bool isLayerAVisible;
  final bool isLayerBVisible;
  final bool isLayerCVisible;
  final double layerAOpacity;
  final double layerBOpacity;
  final double layerCOpacity;
  final ui.ImageShader? tone30Shader;
  final ui.ImageShader? tone60Shader;
  final ui.ImageShader? tone80Shader;
  final int canvasRevision;
  final Size canvasSize;
  final Offset canvasVisualOffset;

  DynamicLayerPainter({
    required this.allLines,
    required this.isLayerAVisible,
    required this.isLayerBVisible,
    required this.isLayerCVisible,
    required this.layerAOpacity,
    required this.layerBOpacity,
    required this.layerCOpacity,
    required this.tone30Shader,
    required this.tone60Shader,
    required this.tone80Shader,
    required this.canvasRevision,
    required this.canvasSize,
    required this.canvasVisualOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final Offset snappedVisualOffset = pixelOffset(canvasVisualOffset);
    canvas.translate(snappedVisualOffset.dx, snappedVisualOffset.dy);
    _drawLayer(
      canvas,
      DrawingLayer.layerA,
      isVisible: isLayerAVisible,
      opacity: layerAOpacity,
    );
    _drawLayer(
      canvas,
      DrawingLayer.layerB,
      isVisible: isLayerBVisible,
      opacity: layerBOpacity,
    );
    _drawLayer(
      canvas,
      DrawingLayer.layerC,
      isVisible: isLayerCVisible,
      opacity: layerCOpacity,
    );
    canvas.restore();
  }

  void _drawLayer(
    Canvas canvas,
    DrawingLayer layer, {
    required bool isVisible,
    required double opacity,
  }) {
    if (!isVisible || opacity <= 0.0) {
      return;
    }
    if (opacity < 1.0) {
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
    }
    LayerCompositePainter.paintSourceContentsUpTo(
      canvas,
      layer,
      kLayerCompositeMaxSequence,
      canvasSize: canvasSize,
      allLines: allLines,
      allPlacements: const <LayerPlacement>[],
      layerABaseImage: null,
      layerBBaseImage: null,
      layerCBaseImage: null,
      layerABaseSampling: RasterSamplingMode.pixelated,
      layerBBaseSampling: RasterSamplingMode.pixelated,
      layerCBaseSampling: RasterSamplingMode.pixelated,
      tone30Shader: tone30Shader,
      tone60Shader: tone60Shader,
      tone80Shader: tone80Shader,
      cacheRevision: canvasRevision,
    );
    if (opacity < 1.0) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant DynamicLayerPainter oldDelegate) {
    return canvasRevision != oldDelegate.canvasRevision ||
        canvasSize != oldDelegate.canvasSize ||
        canvasVisualOffset != oldDelegate.canvasVisualOffset;
  }
}

class CanvasOverlayPainter extends CustomPainter {
  final List<Offset> lassoDraft;
  final bool isDrawingLasso;
  final ToolType currentTool;
  final double currentStrokeWidth;
  final Offset? shapeStart;
  final Offset? shapeEnd;
  final double linesStartPointRatioA;
  final double linesStartPointRatioB;
  final Offset? radialPreviewCenter;
  final double? radialPreviewStartAngle;
  final double radialPreviewSweepAngle;
  final double radialPreviewRadius;
  final int radialLineCountA;
  final int radialLineCountB;
  final double radialOffsetAngleA;
  final double radialOffsetAngleB;
  final int canvasRevision;
  final Size canvasSize;
  final Offset canvasVisualOffset;

  CanvasOverlayPainter({
    required this.lassoDraft,
    required this.isDrawingLasso,
    required this.currentTool,
    required this.currentStrokeWidth,
    required this.shapeStart,
    required this.shapeEnd,
    required this.linesStartPointRatioA,
    required this.linesStartPointRatioB,
    required this.radialPreviewCenter,
    required this.radialPreviewStartAngle,
    required this.radialPreviewSweepAngle,
    required this.radialPreviewRadius,
    required this.radialLineCountA,
    required this.radialLineCountB,
    required this.radialOffsetAngleA,
    required this.radialOffsetAngleB,
    required this.canvasRevision,
    required this.canvasSize,
    required this.canvasVisualOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final Offset snappedVisualOffset = pixelOffset(canvasVisualOffset);
    canvas.translate(snappedVisualOffset.dx, snappedVisualOffset.dy);
    if (isDrawingLasso && lassoDraft.length > 1) {
      _drawLassoDraft(canvas);
    }
    if (_isShapeTool(currentTool) && shapeStart != null && shapeEnd != null) {
      _drawShapeGuide(canvas, currentTool, shapeStart!, shapeEnd!);
    }
    if (currentTool == ToolType.radial && radialPreviewCenter != null) {
      _drawRadialPreview(canvas);
    }
    canvas.restore();
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

  void _drawRadialPreview(Canvas canvas) {
    final Offset center = radialPreviewCenter!;
    final Paint crossPaint = Paint()
      ..color = const Color(0xFFFF4DB8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawLine(
      center + const Offset(-8, -8),
      center + const Offset(8, 8),
      crossPaint,
    );
    canvas.drawLine(
      center + const Offset(-8, 8),
      center + const Offset(8, -8),
      crossPaint,
    );

    if (radialPreviewRadius <= 0.0) {
      return;
    }

    final Path radiusPath = Path()
      ..addOval(
        Rect.fromCircle(center: center, radius: radialPreviewRadius),
      );
    final Paint radiusPaint = Paint()
      ..color = const Color(0x66FF4DB8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    _drawDashedPath(
      canvas,
      radiusPath,
      radiusPaint,
      dashLength: 7,
      gapLength: 5,
    );

    for (final _RadialPreviewSegment segment in _buildRadialPreviewSegments()) {
      canvas.drawLine(
        segment.start,
        segment.end,
        Paint()
          ..color = switch (segment.groupIndex) {
            0 => const Color(0xC0686830),
            _ => const Color(0xA8686830),
          }
          ..strokeWidth = currentStrokeWidth.clamp(1.0, 30.0),
      );
    }
  }

  List<_RadialPreviewSegment> _buildRadialPreviewSegments() {
    final Offset? center = radialPreviewCenter;
    final double? startAngle = radialPreviewStartAngle;
    if (center == null ||
        startAngle == null ||
        radialPreviewRadius <= 0.0 ||
        radialPreviewSweepAngle <= 0.0) {
      return const <_RadialPreviewSegment>[];
    }

    final List<_RadialPreviewSegment> segments = <_RadialPreviewSegment>[];
    segments.addAll(
      _buildRadialPreviewSegmentsForGroup(
        center: center,
        startAngle: startAngle,
        lineCount: radialLineCountA,
        visibleLengthRatio: linesStartPointRatioA,
        offsetAngle: radialOffsetAngleA,
        groupIndex: 0,
        shiftHalfStep: false,
      ),
    );
    segments.addAll(
      _buildRadialPreviewSegmentsForGroup(
        center: center,
        startAngle: startAngle,
        lineCount: radialLineCountB,
        visibleLengthRatio: linesStartPointRatioB,
        offsetAngle: radialOffsetAngleB,
        groupIndex: 1,
        shiftHalfStep: true,
      ),
    );
    return segments;
  }

  List<_RadialPreviewSegment> _buildRadialPreviewSegmentsForGroup({
    required Offset center,
    required double startAngle,
    required int lineCount,
    required double visibleLengthRatio,
    required double offsetAngle,
    required int groupIndex,
    required bool shiftHalfStep,
  }) {
    if (lineCount <= 0) {
      return const <_RadialPreviewSegment>[];
    }

    final List<_RadialPreviewSegment> segments = <_RadialPreviewSegment>[];
    final double step = radialPreviewSweepAngle / lineCount;
    final double basePhase = shiftHalfStep ? step / 2.0 : 0.0;
    final double startRadius =
        radialPreviewRadius * (1.0 - visibleLengthRatio.clamp(0.0, 1.0));
    for (int index = 0; index < lineCount; index++) {
      final double angle =
          startAngle + basePhase + (step * index) + offsetAngle;
      final Offset end = _clampRayToCanvas(
        center,
        _pointAlongAngle(center, angle, radialPreviewRadius),
      );
      final double effectiveRadius = (end - center).distance;
      if (effectiveRadius <= 0.0) {
        continue;
      }
      final double clampedStartRadius =
          startRadius.clamp(0.0, effectiveRadius).toDouble();
      segments.add(
        _RadialPreviewSegment(
          start: _pointAlongAngle(center, angle, clampedStartRadius),
          end: end,
          groupIndex: groupIndex,
        ),
      );
    }
    return segments;
  }

  Offset _pointAlongAngle(Offset center, double angle, double radius) {
    return Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
  }

  Offset _clampRayToCanvas(Offset inside, Offset candidate) {
    final bool isInsideCanvasBounds = candidate.dx >= 0.0 &&
        candidate.dy >= 0.0 &&
        candidate.dx <= canvasSize.width &&
        candidate.dy <= canvasSize.height;
    if (isInsideCanvasBounds) {
      return candidate;
    }

    final double dx = candidate.dx - inside.dx;
    final double dy = candidate.dy - inside.dy;
    if (dx == 0.0 && dy == 0.0) {
      return inside;
    }

    double t = 1.0;
    if (dx > 0.0) {
      t = math.min(t, (canvasSize.width - inside.dx) / dx);
    } else if (dx < 0.0) {
      t = math.min(t, (0.0 - inside.dx) / dx);
    }
    if (dy > 0.0) {
      t = math.min(t, (canvasSize.height - inside.dy) / dy);
    } else if (dy < 0.0) {
      t = math.min(t, (0.0 - inside.dy) / dy);
    }

    return Offset(
      inside.dx + dx * t,
      inside.dy + dy * t,
    );
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint,
      {double dashLength = 8, double gapLength = 6}) {
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      final double length = metric.length;
      while (distance < length) {
        final double next = distance + dashLength;
        final Path segment =
            metric.extractPath(distance, next.clamp(0, length));
        canvas.drawPath(segment, paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CanvasOverlayPainter oldDelegate) {
    return canvasRevision != oldDelegate.canvasRevision ||
        canvasSize != oldDelegate.canvasSize ||
        canvasVisualOffset != oldDelegate.canvasVisualOffset;
  }
}

class DrawingPainter extends CustomPainter {
  final List<DrawnLine> allLines;
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
  final double currentStrokeWidth;
  final Offset? shapeStart;
  final Offset? shapeEnd;
  final double linesStartPointRatioA;
  final double linesStartPointRatioB;
  final Offset? radialPreviewCenter;
  final double? radialPreviewStartAngle;
  final double radialPreviewSweepAngle;
  final double radialPreviewRadius;
  final int radialLineCountA;
  final int radialLineCountB;
  final double radialOffsetAngleA;
  final double radialOffsetAngleB;
  final int canvasRevision;
  final int layerContentRevision;
  final Size canvasSize;
  final Offset canvasVisualOffset;

  DrawingPainter({
    required this.allLines,
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
    required this.currentStrokeWidth,
    required this.shapeStart,
    required this.shapeEnd,
    required this.linesStartPointRatioA,
    required this.linesStartPointRatioB,
    required this.radialPreviewCenter,
    required this.radialPreviewStartAngle,
    required this.radialPreviewSweepAngle,
    required this.radialPreviewRadius,
    required this.radialLineCountA,
    required this.radialLineCountB,
    required this.radialOffsetAngleA,
    required this.radialOffsetAngleB,
    required this.canvasRevision,
    required this.layerContentRevision,
    required this.canvasSize,
    required this.canvasVisualOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ★ ここを削除（またはコメントアウト） ★
    // canvas.drawColor(Colors.white, BlendMode.srcOver);

    canvas.save();
    final Offset snappedVisualOffset = pixelOffset(canvasVisualOffset);
    canvas.translate(snappedVisualOffset.dx, snappedVisualOffset.dy);
    final Rect canvasBounds =
        Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height);

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
      final double previewOpacity =
          selectionVisible && selectionOpacity > 0 ? selectionOpacity : 1.0;
      // Keep the floating selection visible even when its source layer is
      // hidden, otherwise the lasso appears to stop working.
      final bool needsSelectionLayer =
          previewOpacity < 1.0 || selection!.isVectorSelection;
      if (needsSelectionLayer) {
        canvas.saveLayer(
          canvasBounds,
          Paint()..color = Colors.white.withValues(alpha: previewOpacity),
        );
      }
      _paintSelection(
        canvas,
        selection!,
      );
      if (needsSelectionLayer) {
        canvas.restore();
      }
      _paintSelectionOverlay(canvas, selection!, handles);
    }
    if (isDrawingLasso && lassoDraft.length > 1) {
      _drawLassoDraft(canvas);
    }
    if (_isShapeTool(currentTool) && shapeStart != null && shapeEnd != null) {
      _drawShapeGuide(canvas, currentTool, shapeStart!, shapeEnd!);
    }
    if (currentTool == ToolType.radial && radialPreviewCenter != null) {
      _drawRadialPreview(canvas);
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
    final bool needsIsolatedLayer = holePath != null ||
        opacity < 1.0 ||
        LayerCompositePainter.layerRequiresIsolation(
          layer,
          allLines: allLines,
          allPlacements: placements,
          cacheRevision: layerContentRevision,
        );
    if (needsIsolatedLayer) {
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
    }
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
    if (needsIsolatedLayer) {
      canvas.restore();
    }
  }

  void _paintCommittedPlacementsForLayer(Canvas canvas, DrawingLayer layer) {
    LayerCompositePainter.paintSourceContentsUpTo(
      canvas,
      layer,
      kLayerCompositeMaxSequence,
      canvasSize: canvasSize,
      allLines: allLines,
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
      cacheRevision: layerContentRevision,
    );
  }

  void _paintSelection(
    Canvas canvas,
    LassoSelection selection,
  ) {
    LayerCompositePainter.paintLassoSelection(
      canvas,
      selection,
      canvasSize: canvasSize,
      allLines: allLines,
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
      cacheRevision: layerContentRevision,
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

  void _drawRadialPreview(Canvas canvas) {
    final Offset center = radialPreviewCenter!;
    final Paint crossPaint = Paint()
      ..color = const Color(0xFFFF4DB8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawLine(
      center + const Offset(-8, -8),
      center + const Offset(8, 8),
      crossPaint,
    );
    canvas.drawLine(
      center + const Offset(-8, 8),
      center + const Offset(8, -8),
      crossPaint,
    );

    if (radialPreviewRadius <= 0.0) {
      return;
    }

    final Path radiusPath = Path()
      ..addOval(
        Rect.fromCircle(center: center, radius: radialPreviewRadius),
      );
    final Paint radiusPaint = Paint()
      ..color = const Color(0x66FF4DB8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    _drawDashedPath(
      canvas,
      radiusPath,
      radiusPaint,
      dashLength: 7,
      gapLength: 5,
    );

    for (final _RadialPreviewSegment segment in _buildRadialPreviewSegments()) {
      canvas.drawLine(
        segment.start,
        segment.end,
        Paint()
          ..color = switch (segment.groupIndex) {
            0 => const Color(0xC0686830),
            _ => const Color(0xA8686830),
          }
          ..strokeWidth = currentStrokeWidth.clamp(1.0, 30.0),
      );
    }
  }

  List<_RadialPreviewSegment> _buildRadialPreviewSegments() {
    final Offset? center = radialPreviewCenter;
    final double? startAngle = radialPreviewStartAngle;
    if (center == null ||
        startAngle == null ||
        radialPreviewRadius <= 0.0 ||
        radialPreviewSweepAngle <= 0.0) {
      return const <_RadialPreviewSegment>[];
    }

    final List<_RadialPreviewSegment> segments = <_RadialPreviewSegment>[];
    segments.addAll(
      _buildRadialPreviewSegmentsForGroup(
        center: center,
        startAngle: startAngle,
        lineCount: radialLineCountA,
        visibleLengthRatio: linesStartPointRatioA,
        offsetAngle: radialOffsetAngleA,
        groupIndex: 0,
        shiftHalfStep: false,
      ),
    );
    segments.addAll(
      _buildRadialPreviewSegmentsForGroup(
        center: center,
        startAngle: startAngle,
        lineCount: radialLineCountB,
        visibleLengthRatio: linesStartPointRatioB,
        offsetAngle: radialOffsetAngleB,
        groupIndex: 1,
        shiftHalfStep: true,
      ),
    );
    return segments;
  }

  List<_RadialPreviewSegment> _buildRadialPreviewSegmentsForGroup({
    required Offset center,
    required double startAngle,
    required int lineCount,
    required double visibleLengthRatio,
    required double offsetAngle,
    required int groupIndex,
    required bool shiftHalfStep,
  }) {
    if (lineCount <= 0) {
      return const <_RadialPreviewSegment>[];
    }

    final List<_RadialPreviewSegment> segments = <_RadialPreviewSegment>[];
    final double step = radialPreviewSweepAngle / lineCount;
    final double basePhase = shiftHalfStep ? step / 2.0 : 0.0;
    final double startRadius =
        radialPreviewRadius * (1.0 - visibleLengthRatio.clamp(0.0, 1.0));
    for (int index = 0; index < lineCount; index++) {
      final double angle =
          startAngle + basePhase + (step * index) + offsetAngle;
      final Offset end = _clampRayToCanvas(
        center,
        _pointAlongAngle(center, angle, radialPreviewRadius),
      );
      final double effectiveRadius = (end - center).distance;
      if (effectiveRadius <= 0.0) {
        continue;
      }
      final double clampedStartRadius =
          startRadius.clamp(0.0, effectiveRadius).toDouble();
      segments.add(
        _RadialPreviewSegment(
          start: _pointAlongAngle(center, angle, clampedStartRadius),
          end: end,
          groupIndex: groupIndex,
        ),
      );
    }
    return segments;
  }

  Offset _pointAlongAngle(Offset center, double angle, double radius) {
    return Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
  }

  Offset _clampRayToCanvas(Offset inside, Offset candidate) {
    final bool isInsideCanvasBounds = candidate.dx >= 0.0 &&
        candidate.dy >= 0.0 &&
        candidate.dx <= canvasSize.width &&
        candidate.dy <= canvasSize.height;
    if (isInsideCanvasBounds) {
      return candidate;
    }

    final double dx = candidate.dx - inside.dx;
    final double dy = candidate.dy - inside.dy;
    if (dx == 0.0 && dy == 0.0) {
      return inside;
    }

    double t = 1.0;
    if (dx > 0.0) {
      t = math.min(t, (canvasSize.width - inside.dx) / dx);
    } else if (dx < 0.0) {
      t = math.min(t, (0.0 - inside.dx) / dx);
    }
    if (dy > 0.0) {
      t = math.min(t, (canvasSize.height - inside.dy) / dy);
    } else if (dy < 0.0) {
      t = math.min(t, (0.0 - inside.dy) / dy);
    }

    return Offset(
      inside.dx + dx * t,
      inside.dy + dy * t,
    );
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

  bool _shouldRepaintFromSnapshots(DrawingPainter oldDelegate) {
    return canvasRevision != oldDelegate.canvasRevision ||
        canvasSize != oldDelegate.canvasSize ||
        canvasVisualOffset != oldDelegate.canvasVisualOffset;
  }

  @override
  bool shouldRepaint(covariant DrawingPainter oldDelegate) {
    return _shouldRepaintFromSnapshots(oldDelegate);
/*
    // データが変更された場合のみ再描画（ソート済みリストの内容も比較）
    if (layerALines.length != oldDelegate.layerALines.length ||
        layerBLines.length != oldDelegate.layerBLines.length ||
        layerCLines.length != oldDelegate.layerCLines.length ||
        placements.length != oldDelegate.placements.length ||
        isDrawingLasso != oldDelegate.isDrawingLasso ||
        lassoDraft.length != oldDelegate.lassoDraft.length ||
        selection?.translation != oldDelegate.selection?.translation ||
        selection?.rotation != oldDelegate.selection?.rotation ||
        selection?.scaleX != oldDelegate.selection?.scaleX ||
        selection?.scaleY != oldDelegate.selection?.scaleY ||
        shapeStart != oldDelegate.shapeStart ||
        shapeEnd != oldDelegate.shapeEnd ||
        currentTool != oldDelegate.currentTool ||
        isLayerAVisible != oldDelegate.isLayerAVisible ||
        isLayerBVisible != oldDelegate.isLayerBVisible ||
        isLayerCVisible != oldDelegate.isLayerCVisible ||
        layerAOpacity != oldDelegate.layerAOpacity ||
        layerBOpacity != oldDelegate.layerBOpacity ||
        layerCOpacity != oldDelegate.layerCOpacity ||
        layerABaseImage != oldDelegate.layerABaseImage ||
        layerBBaseImage != oldDelegate.layerBBaseImage ||
        layerCBaseImage != oldDelegate.layerCBaseImage) {
      return true;
    }
    // リスト内容が変わった場合も再描画が必要
    for (int i = 0; i < _allLinesSorted.length; i++) {
      if (i >= oldDelegate._allLinesSorted.length ||
          _allLinesSorted[i] != oldDelegate._allLinesSorted[i]) {
        return true;
      }
    }
    return false;
*/
  }
}

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/drawing.dart';
import '../providers/drawing_provider.dart';

class DrawingCanvas extends StatefulWidget {
  final ValueChanged<Offset>? onTwoFingerPan;
  const DrawingCanvas({super.key, this.onTwoFingerPan});
  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  Offset? _lastOffset;
  Size? _canvasSize;
  SelectionDragState? _dragState;
  final Map<int, Offset> _activeTouchPoints = {};
  Offset? _lastTwoFingerFocalPoint;
  //もっと長い距離をかけて細くしたい場合は、以下の定数を大きくします。
  static const double _minHandleDistance = 60.0;// 入り
  static const double _rotationSoftRadius = 80.0;// 抜き（払い）は特にながく
  static const double _rotationSensitivity = 0.85;

  @override
  Widget build(BuildContext context) {
    return Consumer<DrawingProvider>(
      builder: (context, drawing, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final Size size = Size(constraints.maxWidth, constraints.maxHeight);
            if (_canvasSize != size) {
              _canvasSize = size;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                drawing.setCanvasSize(size);
              });
            }
            return Listener(
              onPointerDown: (event) => _handlePointerDown(event, drawing),
              onPointerMove: (event) => _handlePointerMove(event, drawing),
              onPointerUp: _handlePointerUpOrCancel,
              onPointerCancel: _handlePointerUpOrCancel,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _handleTapDown(details, drawing),
                onPanStart: (details) => _handlePanStart(details, drawing),
                onPanUpdate: (details) => _handlePanUpdate(details, drawing),
                onPanEnd: (_) => _handlePanEnd(drawing),
                onPanCancel: () => _handlePanEnd(drawing),
                child: CustomPaint(
                  painter: DrawingPainter(
                    layerALines: drawing.layerALines,
                    layerBLines: drawing.layerBLines,
                    isLayerAVisible: drawing.isLayerAVisible,
                    isLayerBVisible: drawing.isLayerBVisible,
                    layerAOpacity: drawing.layerAOpacity,
                    layerBOpacity: drawing.layerBOpacity,
                    layerABaseImage: drawing.layerABaseImage,
                    layerBBaseImage: drawing.layerBBaseImage,
                    selection: drawing.selection,
                    lassoDraft: drawing.lassoDraft,
                    isDrawingLasso: drawing.isDrawingLasso,
                    handles: drawing.getSelectionHandles(),
                    currentTool: drawing.currentTool,
                    shapeStart: drawing.shapeStart,
                    shapeEnd: drawing.shapeEnd,
                  ),
                  child: Container(),
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
    final points = _activeTouchPoints.values.toList(growable: false);
    return Offset(
      (points[0].dx + points[1].dx) / 2,
      (points[0].dy + points[1].dy) / 2,
    );
  }

  void _cancelDrawingForTwoFinger(DrawingProvider drawing) {
    _dragState = null;
    _lastOffset = null;
    drawing.endLine();
  }

  void _handlePointerDown(PointerDownEvent event, DrawingProvider drawing) {
    if (event.kind != ui.PointerDeviceKind.touch) return;
    _activeTouchPoints[event.pointer] = event.localPosition;
    if (_isTwoFingerTouchActive) {
      _lastTwoFingerFocalPoint = _twoFingerFocalPoint();
      _cancelDrawingForTwoFinger(drawing);
    }
  }

  void _handlePointerMove(PointerMoveEvent event, DrawingProvider drawing) {
    if (!_activeTouchPoints.containsKey(event.pointer)) return;
    _activeTouchPoints[event.pointer] = event.localPosition;
    if (_isTwoFingerTouchActive) {
      final currentFocal = _twoFingerFocalPoint();
      final lastFocal = _lastTwoFingerFocalPoint;
      if (lastFocal != null) {
        final delta = currentFocal - lastFocal;
        if (delta != Offset.zero) {
          widget.onTwoFingerPan?.call(delta);
        }
      }
      _lastTwoFingerFocalPoint = currentFocal;
      _cancelDrawingForTwoFinger(drawing);
    }
  }

  void _handlePointerUpOrCancel(PointerEvent event) {
    _activeTouchPoints.remove(event.pointer);
    if (_isTwoFingerTouchActive) {
      _lastTwoFingerFocalPoint = _twoFingerFocalPoint();
    } else {
      _lastTwoFingerFocalPoint = null;
    }
  }

  Future<void> _handleTapDown(TapDownDetails details, DrawingProvider drawing) async {
    if (drawing.currentTool == ToolType.lasso && drawing.selection != null) {
      final handle = drawing.hitTestSelection(details.localPosition);
      if (handle == SelectionHandle.mirror) {
        drawing.beginSelectionInteraction();
        drawing.flipSelectionHorizontal();
        return;
      }
      if (handle == SelectionHandle.none &&
          drawing.shouldFinishSelection(details.localPosition)) {
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
    final pos = details.localPosition;
    _lastOffset = pos;
    if (drawing.currentTool == ToolType.lasso) {
      if (drawing.selection != null) {
        final handle = drawing.hitTestSelection(pos);
        if (handle != SelectionHandle.none) {
          drawing.beginSelectionInteraction();
          if (handle == SelectionHandle.mirror) {
            drawing.flipSelectionHorizontal();
            return;
          }
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
    final pos = details.localPosition;
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

  Future<void> _handlePanEnd(DrawingProvider drawing) async {
    if (_isTwoFingerTouchActive) {
      _dragState = null;
      _lastOffset = null;
      return;
    }
    if (drawing.currentTool == ToolType.lasso) {
      if (drawing.isDrawingLasso && _canvasSize != null) {
        await drawing.finishLasso(_canvasSize!);
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
    final double cross = startVec.dx * currentVec.dy - startVec.dy * currentVec.dx;
    final double dot = startVec.dx * currentVec.dx + startVec.dy * currentVec.dy;
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
        // Mirror toggle handled on tap/drag start; avoid continuous updates.
        drawing.flipSelectionHorizontal();
        _dragState = null;
        break;
      case SelectionHandle.cornerTL:
      case SelectionHandle.cornerTR:
      case SelectionHandle.cornerBR:
      case SelectionHandle.cornerBL:
        final localCurrent = _toLocalAtDragStart(currentPos, state, selection.baseRect);
        final startVec = state.startLocal - center;
        final currentVec = localCurrent - center;
        final startLen = startVec.distance;
        final currentLen = currentVec.distance;
        if (startLen > 0.001 && currentLen > 0.001) {
          final double safeStartLen = math.max(startLen, _minHandleDistance);
          final double safeCurrentLen = math.max(currentLen, _minHandleDistance);
          final scale = safeCurrentLen / safeStartLen;
          final double baseAngle = _stableAngleDelta(startVec, currentVec);
          final double radiusFactor = (math.min(startLen, currentLen) / _rotationSoftRadius).clamp(0.35, 1.0);
          final double rotationDelta = baseAngle * radiusFactor * _rotationSensitivity;
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
        final localCurrent = _toLocalAtDragStart(currentPos, state, selection.baseRect);
        final startVec = state.startLocal - center;
        final currentVec = localCurrent - center;
        final startAxis = startVec.dx.abs();
        final currentAxis = currentVec.dx.abs();
        if (startAxis > 0.001) {
          final double safeStartAxis = math.max(startAxis, _minHandleDistance);
          final double safeCurrentAxis = math.max(currentAxis, _minHandleDistance);
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
        final localCurrent = _toLocalAtDragStart(currentPos, state, selection.baseRect);
        final startVec = state.startLocal - center;
        final currentVec = localCurrent - center;
        final startAxis = startVec.dy.abs();
        final currentAxis = currentVec.dy.abs();
        if (startAxis > 0.001) {
          final double safeStartAxis = math.max(startAxis, _minHandleDistance);
          final double safeCurrentAxis = math.max(currentAxis, _minHandleDistance);
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
  final bool isLayerAVisible;
  final bool isLayerBVisible;
  final double layerAOpacity;
  final double layerBOpacity;
  final ui.Image? layerABaseImage;
  final ui.Image? layerBBaseImage;
  final LassoSelection? selection;
  final List<Offset> lassoDraft;
  final bool isDrawingLasso;
  final Map<SelectionHandle, Offset> handles;
  final ToolType currentTool;
  final Offset? shapeStart;
  final Offset? shapeEnd;

  DrawingPainter({
    required this.layerALines,
    required this.layerBLines,
    required this.isLayerAVisible,
    required this.isLayerBVisible,
    required this.layerAOpacity,
    required this.layerBOpacity,
    required this.layerABaseImage,
    required this.layerBBaseImage,
    required this.selection,
    required this.lassoDraft,
    required this.isDrawingLasso,
    required this.handles,
    required this.currentTool,
    required this.shapeStart,
    required this.shapeEnd,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ★ ここを削除（またはコメントアウト） ★
    // canvas.drawColor(Colors.white, BlendMode.srcOver);

    _drawLayer(
      canvas,
      size,
      layerABaseImage,
      layerALines,
      isVisible: isLayerAVisible,
      opacity: layerAOpacity,
    );
    _drawLayer(
      canvas,
      size,
      layerBBaseImage,
      layerBLines,
      isVisible: isLayerBVisible,
      opacity: layerBOpacity,
    );

    if (selection != null) {
      final bool inLayerA = selection!.layer == DrawingLayer.layerA;
      final bool selectionVisible = inLayerA ? isLayerAVisible : isLayerBVisible;
      final double selectionOpacity = inLayerA ? layerAOpacity : layerBOpacity;
      if (selectionVisible && selectionOpacity > 0) {
        canvas.saveLayer(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..color = Colors.white.withValues(alpha: selectionOpacity),
        );
        _paintSelection(canvas, selection!);
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
  }

  void _drawLayer(
    Canvas canvas,
    Size size,
    ui.Image? baseImage,
    List<DrawnLine> lines, {
    required bool isVisible,
    required double opacity,
  }) {
    if (!isVisible || opacity <= 0) return;
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );
    if (baseImage != null) {
      canvas.drawImage(baseImage, Offset.zero, Paint());
    }
    _drawLines(canvas, lines);
    canvas.restore();
  }

  void _drawLines(Canvas canvas, List<DrawnLine> lines) {
    final paint = Paint()
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final line in lines) {
      paint
        ..color = _toneAwareLineColor(line).withValues(alpha: line.eraserAlpha)
        ..blendMode = line.isEraser ? BlendMode.dstOut : BlendMode.srcOver;

      switch (line.tool) {
        case ToolType.rect:
        case ToolType.fillRect:
          if (line.shapeRect == null) continue;
          paint
            ..style = line.tool == ToolType.fillRect ? PaintingStyle.fill : PaintingStyle.stroke
            ..strokeCap = StrokeCap.butt
            ..strokeJoin = StrokeJoin.miter
            ..strokeWidth = line.width;
          canvas.drawRect(line.shapeRect!, paint);
          break;
        case ToolType.circle:
        case ToolType.fillCircle:
          if (line.shapeRect == null) continue;
          paint
            ..style = line.tool == ToolType.fillCircle ? PaintingStyle.fill : PaintingStyle.stroke
            ..strokeWidth = line.width;
          canvas.drawOval(line.shapeRect!, paint);
          break;
        case ToolType.line:
          if (line.points.length < 2) continue;
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = line.points.first.width
            ..strokeCap = StrokeCap.butt
            ..strokeJoin = StrokeJoin.miter;
          final path = Path()
            ..moveTo(line.points.first.offset.dx, line.points.first.offset.dy)
            ..lineTo(line.points.last.offset.dx, line.points.last.offset.dy);
          canvas.drawPath(path, paint);
          break;
        case ToolType.dot30:
        case ToolType.dot60:
        case ToolType.dot80:
          if (line.points.isEmpty) continue;
          paint
            ..style = PaintingStyle.fill
            ..strokeWidth = 1;
          for (final p in line.points) {
            canvas.drawCircle(p.offset, line.width / 2, paint);
          }
          break;
        default:
          if (line.points.length < 2) continue;
          if (!line.variableWidth) {
            final path = _buildSmoothPath(line.points);
            paint
              ..style = PaintingStyle.stroke
              ..strokeWidth = line.width;
            canvas.drawPath(path, paint);
          } else {
            final path = _buildVariableWidthRibbon(line.points);
            paint
              ..style = PaintingStyle.fill
              ..strokeWidth = 1
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round;
            canvas.drawPath(path, paint);
          }
      }
    }
  }

  Color _toneAwareLineColor(DrawnLine line) {
    switch (line.tool) {
      case ToolType.tone30:
        return Colors.grey.shade300;
      case ToolType.tone60:
        return Colors.grey.shade600;
      case ToolType.tone80:
        return Colors.grey.shade800;
      default:
        return line.color;
    }
  }

  void _paintSelection(Canvas canvas, LassoSelection selection) {
    final Rect rect = selection.baseRect;
    final Offset center = rect.center + selection.translation;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(selection.rotation);
    canvas.scale(selection.scaleX, selection.scaleY);
    canvas.translate(-rect.center.dx, -rect.center.dy);
    paintImage(
      canvas: canvas,
      rect: rect,
      image: selection.image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.high,
    );
    canvas.restore();
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
    final handlePaint = Paint()..color = Colors.black;
    for (final entry in handles.entries) {
      if (entry.key == SelectionHandle.mirror) continue;
      final rect = Rect.fromCenter(
        center: entry.value,
        width: handleSize,
        height: handleSize,
      );
      canvas.drawRect(rect, handlePaint);
    }

    // Mirror button: draw ◀▷ text in system font inside a small rounded rect
    if (handles.containsKey(SelectionHandle.mirror)) {
      final pos = handles[SelectionHandle.mirror]!;
      final rect = Rect.fromCenter(center: pos, width: 24, height: 20);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      final bg = Paint()..color = Colors.white;
      canvas.drawRRect(rrect, bg);
      canvas.drawRRect(rrect, paint);
      final textPainter = TextPainter(
        text: const TextSpan(
          text: '◀▷',
          style: TextStyle(fontSize: 12, color: Colors.black),
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

  List<Point> _lowPassFilter(List<Point> points, {double factor = 0.55}) {
    if (points.length < 2) return points;
    final result = <Point>[points.first];
    for (int i = 1; i < points.length; i++) {
      final previous = result.last;
      final current = points[i];
      final filteredOffset = Offset.lerp(previous.offset, current.offset, factor)!;
      result.add(Point(filteredOffset, current.width));
    }
    return result;
  }

  Path _buildSmoothPath(List<Point> points) {
    final path = Path();
    if (points.isEmpty) return path;
    if (points.length == 1) {
      path.addOval(Rect.fromCircle(center: points.first.offset, radius: points.first.width / 2));
      return path;
    }
    final filtered = _lowPassFilter(points, factor: 0.6);
    path.moveTo(filtered.first.offset.dx, filtered.first.offset.dy);
    for (int i = 1; i < filtered.length - 1; i++) {
      final current = filtered[i].offset;
      final next = filtered[i + 1].offset;
      final mid = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
    }
    path.lineTo(filtered.last.offset.dx, filtered.last.offset.dy);
    return path;
  }

  Path _buildVariableWidthRibbon(List<Point> points) {
    if (points.length < 2) return Path();
    // 修正後（数値を小さくします）
    // 0.1〜0.2にすると、前の点との平均を強く取るようになり、ボコボコが消えます。
    final filtered = _lowPassFilter(points, factor: 0.15);
    final dense = _catmullRomDensePoints(filtered, samples: 10);
    final left = <Offset>[];
    final right = <Offset>[];
    for (int i = 0; i < dense.length; i++) {
      final p = dense[i].offset;
      final w = dense[i].width;
      Offset dir;
      if (i == 0) {
        dir = dense[i + 1].offset - p;
      } else if (i == dense.length - 1) {
        dir = p - dense[i - 1].offset;
      } else {
        dir = dense[i + 1].offset - dense[i - 1].offset;
      }
      final len = dir.distance;
      if (len < 0.001) continue;
      final n = Offset(-dir.dy / len, dir.dx / len);
      final halfW = w / 2;
      left.add(p + n * halfW);
      right.add(p - n * halfW);
    }
    final path = Path();
    if (left.isEmpty || right.isEmpty) return path;
    path.moveTo(left.first.dx, left.first.dy);
    for (int i = 1; i < left.length; i++) {
      path.lineTo(left[i].dx, left[i].dy);
    }
    for (int i = right.length - 1; i >= 0; i--) {
      path.lineTo(right[i].dx, right[i].dy);
    }
    path.close();
    return path;
  }

  List<Point> _catmullRomDensePoints(List<Point> pts, {int samples = 8}) {
    if (pts.length < 2) return pts;
    final List<Point> dense = [];
    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = i == 0 ? pts[i] : pts[i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : pts[i + 1];
      for (int s = 0; s < samples; s++) {
        final t = s / samples;
        final t2 = t * t;
        final t3 = t2 * t;
        Offset pos = Offset(
          0.5 *
              ((2 * p1.offset.dx) +
                  (-p0.offset.dx + p2.offset.dx) * t +
                  (2 * p0.offset.dx - 5 * p1.offset.dx + 4 * p2.offset.dx - p3.offset.dx) * t2 +
                  (-p0.offset.dx + 3 * p1.offset.dx - 3 * p2.offset.dx + p3.offset.dx) * t3),
          0.5 *
              ((2 * p1.offset.dy) +
                  (-p0.offset.dy + p2.offset.dy) * t +
                  (2 * p0.offset.dy - 5 * p1.offset.dy + 4 * p2.offset.dy - p3.offset.dy) * t2 +
                  (-p0.offset.dy + 3 * p1.offset.dy - 3 * p2.offset.dy + p3.offset.dy) * t3),
        );
        final width = ui.lerpDouble(p1.width, p2.width, t)!;
        dense.add(Point(pos, width));
      }
    }
    dense.add(pts.last);
    return dense;
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

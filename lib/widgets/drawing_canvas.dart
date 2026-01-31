import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/drawing.dart';
import '../providers/drawing_provider.dart';

class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({super.key});

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  Offset? _lastOffset;
  Size? _canvasSize;
  SelectionDragState? _dragState;

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
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _handleTapDown(details, drawing),
              onPanStart: (details) => _handlePanStart(details, drawing),
              onPanUpdate: (details) => _handlePanUpdate(details, drawing),
              onPanEnd: (_) => _handlePanEnd(drawing),
              onPanCancel: () => _handlePanEnd(drawing),
              child: CustomPaint(
                painter: DrawingPainter(
                  lines: drawing.lines,
                  baseImage: drawing.baseImage,
                  selection: drawing.selection,
                  lassoDraft: drawing.lassoDraft,
                  isDrawingLasso: drawing.isDrawingLasso,
                  handles: drawing.getSelectionHandles(),
                ),
                child: Container(),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleTapDown(TapDownDetails details, DrawingProvider drawing) async {
    if (drawing.currentTool == ToolType.lasso && drawing.selection != null) {
      final handle = drawing.hitTestSelection(details.localPosition);
      if (handle == SelectionHandle.mirror) {
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
    final pos = details.localPosition;
    _lastOffset = pos;

    if (drawing.currentTool == ToolType.lasso) {
      if (drawing.selection != null) {
        final handle = drawing.hitTestSelection(pos);
        if (handle != SelectionHandle.none) {
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
        final localCurrent = selection.toLocal(currentPos);
        final startVec = state.startLocal - center;
        final currentVec = localCurrent - center;
        final startLen = startVec.distance;
        final currentLen = currentVec.distance;
        if (startLen > 0.001 && currentLen > 0.001) {
          final scale = currentLen / startLen;
          final rotationDelta = currentVec.direction - startVec.direction;
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
        final localCurrent = selection.toLocal(currentPos);
        final startVec = state.startLocal - center;
        final currentVec = localCurrent - center;
        final startAxis = startVec.dx.abs();
        final currentAxis = currentVec.dx.abs();
        if (startAxis > 0.001) {
          final scaleX = (currentAxis / startAxis).clamp(0.05, 20.0);
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
        final localCurrent = selection.toLocal(currentPos);
        final startVec = state.startLocal - center;
        final currentVec = localCurrent - center;
        final startAxis = startVec.dy.abs();
        final currentAxis = currentVec.dy.abs();
        if (startAxis > 0.001) {
          final scaleY = (currentAxis / startAxis).clamp(0.05, 20.0);
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
  final List<DrawnLine> lines;
  final ui.Image? baseImage;
  final LassoSelection? selection;
  final List<Offset> lassoDraft;
  final bool isDrawingLasso;
  final Map<SelectionHandle, Offset> handles;

  DrawingPainter({
    required this.lines,
    required this.baseImage,
    required this.selection,
    required this.lassoDraft,
    required this.isDrawingLasso,
    required this.handles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.srcOver);
    if (baseImage != null) {
      canvas.drawImage(baseImage!, Offset.zero, Paint());
    }
    _drawLines(canvas);
    if (selection != null) {
      _paintSelection(canvas, selection!);
      _paintSelectionOverlay(canvas, selection!, handles);
    }
    if (isDrawingLasso && lassoDraft.length > 1) {
      _drawLassoDraft(canvas);
    }
  }

  void _drawLines(Canvas canvas) {
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final line in lines) {
      if (line.points.length < 2) continue;
      paint
        ..color = line.color
        ..blendMode = BlendMode.srcOver;

      final filteredPoints = _lowPassFilter(line.points);
      final smoothedPoints = <Point>[];
      for (int i = 0; i < filteredPoints.length - 1; i++) {
        smoothedPoints.addAll(_interpolatePoints(filteredPoints[i], filteredPoints[i + 1]));
      }
      smoothedPoints.add(filteredPoints.last);

      for (int i = 0; i < smoothedPoints.length - 1; i++) {
        final p1 = smoothedPoints[i];
        final p2 = smoothedPoints[i + 1];
        paint.strokeWidth = (p1.width + p2.width) / 2;
        canvas.drawLine(p1.offset, p2.offset, paint);
      }
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

  List<Point> _interpolatePoints(Point p1, Point p2, {int divisions = 5}) {
    final result = <Point>[p1];
    for (int i = 1; i < divisions; i++) {
      final t = i / divisions;
      final interpolatedOffset = Offset(
        p1.offset.dx + (p2.offset.dx - p1.offset.dx) * t,
        p1.offset.dy + (p2.offset.dy - p1.offset.dy) * t,
      );
      final interpolatedWidth = p1.width + (p2.width - p1.width) * t;
      result.add(Point(interpolatedOffset, interpolatedWidth));
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

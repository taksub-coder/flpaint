import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/drawing.dart';

class DrawingProvider extends ChangeNotifier {
  final List<DrawnLine> _lines = [];
  DrawnLine? _currentLine;
  Offset? _lineStartPoint;

  double _strokeWidth = 5.0;
  ToolType _tool = ToolType.pressure;
  ui.Image? _baseImage;
  Size _canvasSize = Size.zero;

  // Lasso
  final List<Offset> _lassoPoints = [];
  bool _isDrawingLasso = false;
  LassoSelection? _selection;

  List<DrawnLine> get lines => _lines;
  double get strokeWidth => _strokeWidth;
  ToolType get currentTool => _tool;
  ui.Image? get baseImage => _baseImage;
  List<Offset> get lassoDraft => List.unmodifiable(_lassoPoints);
  bool get isDrawingLasso => _isDrawingLasso;
  LassoSelection? get selection => _selection;

  // Pen dynamics constants
  static const double _maxWidthDistance = 14.0;
  static const double _minWidthDistance = 21.0;
  static const double _jitterDistanceThreshold = 2.4;
  static const double _jitterLerpFactor = 0.25;
  static const double _regularLerpFactor = 0.45;
  static const double _tailNoiseDistance = 8.0;
  static const double _tailDirectionCosineThreshold = 0.6;

  void setCanvasSize(Size size) {
    if (_canvasSize == size) return;
    _canvasSize = size;
  }

  void setTool(ToolType tool) {
    _tool = tool;
    notifyListeners();
  }

  void setStrokeWidth(double width) {
    _strokeWidth = width;
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    _currentLine = null;
    _lineStartPoint = null;
    _lassoPoints.clear();
    _isDrawingLasso = false;
    _selection = null;
    _baseImage = null;
    notifyListeners();
  }

  Offset _smoothOffset(Offset rawPoint, {bool forceJitterLerp = false}) {
    final lastStored = _currentLine!.points.last.offset;
    final distanceToLast = (rawPoint - lastStored).distance;
    final t = (forceJitterLerp || distanceToLast < _jitterDistanceThreshold)
        ? _jitterLerpFactor
        : _regularLerpFactor;
    return Offset.lerp(lastStored, rawPoint, t)!;
  }

  void _trimTailNoise() {
    if (_currentLine == null) return;
    final points = _currentLine!.points;

    while (points.length >= 3) {
      final p3 = points[points.length - 1].offset;
      final p2 = points[points.length - 2].offset;
      final p1 = points[points.length - 3].offset;

      final v1 = p2 - p1;
      final v2 = p3 - p2;
      final v1Len = v1.distance;
      final v2Len = v2.distance;

      if (v1Len == 0 || v2Len == 0 || v2Len > _tailNoiseDistance) {
        break;
      }

      final cosTheta = (v1.dx * v2.dx + v1.dy * v2.dy) / (v1Len * v2Len);
      if (cosTheta < _tailDirectionCosineThreshold) {
        points.removeLast();
      } else {
        break;
      }
    }
  }

  void startNewLine(Offset startPoint) {
    if (_tool == ToolType.lasso) return;
    _lineStartPoint = startPoint;
    final color = _tool == ToolType.eraser ? Colors.white : Colors.black;
    final variableWidth = _tool == ToolType.pressure;
    _currentLine = DrawnLine(
      [Point(startPoint, _tool == ToolType.pressure ? 0.1 : _strokeWidth)],
      color: color,
      variableWidth: variableWidth,
      isEraser: _tool == ToolType.eraser,
      isFinished: false,
    );
    _lines.add(_currentLine!);
    notifyListeners();
  }

  void addPoint(Offset point, Offset lastPoint) {
    if (_currentLine == null || _lineStartPoint == null) return;

    final currentPoints = _currentLine!.points;
    final lastStored = currentPoints.last;
    final distanceToLast = (point - lastStored.offset).distance;
    bool isDirectionJitter = false;
    if (currentPoints.length >= 2 && distanceToLast <= _tailNoiseDistance) {
      final previous = currentPoints[currentPoints.length - 2].offset;
      final v1 = lastStored.offset - previous;
      final v2 = point - lastStored.offset;
      final v1Len = v1.distance;
      final v2Len = v2.distance;
      if (v1Len > 0 && v2Len > 0) {
        final cosTheta = (v1.dx * v2.dx + v1.dy * v2.dy) / (v1Len * v2Len);
        isDirectionJitter = cosTheta < _tailDirectionCosineThreshold;
      }
    }
    final smoothedOffset = _smoothOffset(point, forceJitterLerp: isDirectionJitter);

    double width = _strokeWidth;
    if (_currentLine!.variableWidth) {
      final distanceFromStart = (_lineStartPoint! - point).distance;
      if (distanceFromStart <= _maxWidthDistance) {
        width = (distanceFromStart / _maxWidthDistance) * _strokeWidth;
      }
    }

    if (distanceToLast < _jitterDistanceThreshold || isDirectionJitter) {
      currentPoints[currentPoints.length - 1] = Point(smoothedOffset, width);
    } else {
      currentPoints.add(Point(smoothedOffset, width));
    }
    notifyListeners();
  }

  void endLine() {
    if (_currentLine == null) return;

    if (_currentLine!.variableWidth) {
      _trimTailNoise();

      final totalPoints = _currentLine!.points.length;
      final endPoint = _currentLine!.points[totalPoints - 1].offset;

      for (int i = 0; i < totalPoints; i++) {
        final point = _currentLine!.points[i];
        final distanceFromEnd = (point.offset - endPoint).distance;
        if (distanceFromEnd <= _minWidthDistance) {
          final ratio = distanceFromEnd / _minWidthDistance;
          _currentLine!.points[i] = Point(point.offset, point.width * ratio);
        }
      }
    }

    _currentLine!.isFinished = true;
    _currentLine = null;
    _lineStartPoint = null;
    notifyListeners();
  }

  // Lasso creation
  void startLasso(Offset start) {
    _isDrawingLasso = true;
    _lassoPoints
      ..clear()
      ..add(start);
    notifyListeners();
  }

  void extendLasso(Offset point) {
    if (!_isDrawingLasso) return;
    _lassoPoints.add(point);
    notifyListeners();
  }

  Future<void> finishLasso(Size size) async {
    if (!_isDrawingLasso || _lassoPoints.length < 3) {
      _lassoPoints.clear();
      _isDrawingLasso = false;
      notifyListeners();
      return;
    }

    final path = Path()..addPolygon(List.of(_lassoPoints), true);
    final bounds = path.getBounds();
    _lassoPoints.clear();
    _isDrawingLasso = false;

    if (bounds.width < 2 || bounds.height < 2) {
      notifyListeners();
      return;
    }

    final ui.Image source = await _renderBaseAndLines(size);
    final ui.Image selectionImage = await _extractSelection(source, path, bounds);
    final ui.Image background = await _eraseSelection(source, path, size);

    _baseImage = background;
    _lines.clear();
    _selection = LassoSelection(
      image: selectionImage,
      maskPath: path,
      baseRect: bounds,
    );
    notifyListeners();
  }

  Future<ui.Image> _renderBaseAndLines(Size size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.srcOver);
    if (_baseImage != null) {
      canvas.drawImage(_baseImage!, Offset.zero, Paint());
    }
    _drawLines(canvas);
    final picture = recorder.endRecording();
    return picture.toImage(size.width.ceil(), size.height.ceil());
  }

  Future<ui.Image> _extractSelection(ui.Image source, Path path, Rect bounds) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(-bounds.left, -bounds.top);
    canvas.clipPath(path);
    canvas.drawImage(source, Offset.zero, Paint());
    final picture = recorder.endRecording();
    return picture.toImage(bounds.width.ceil(), bounds.height.ceil());
  }

  Future<ui.Image> _eraseSelection(ui.Image source, Path path, Size size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(source, Offset.zero, Paint());
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    canvas.drawPath(path, Paint()..blendMode = BlendMode.clear);
    canvas.restore();
    final picture = recorder.endRecording();
    return picture.toImage(size.width.ceil(), size.height.ceil());
  }

  // Selection manipulation
  Map<SelectionHandle, Offset> _handlePositions(LassoSelection selection) {
    final corners = selection.transformedCorners();
    final bounds = selection.transformedBounds();
    final Map<SelectionHandle, Offset> handles = {
      SelectionHandle.cornerTL: corners[0],
      SelectionHandle.cornerTR: corners[1],
      SelectionHandle.cornerBR: corners[2],
      SelectionHandle.cornerBL: corners[3],
    };
    handles[SelectionHandle.edgeTop] = Offset(
      (corners[0].dx + corners[1].dx) / 2,
      (corners[0].dy + corners[1].dy) / 2,
    );
    handles[SelectionHandle.edgeRight] = Offset(
      (corners[1].dx + corners[2].dx) / 2,
      (corners[1].dy + corners[2].dy) / 2,
    );
    handles[SelectionHandle.edgeBottom] = Offset(
      (corners[2].dx + corners[3].dx) / 2,
      (corners[2].dy + corners[3].dy) / 2,
    );
    handles[SelectionHandle.edgeLeft] = Offset(
      (corners[3].dx + corners[0].dx) / 2,
      (corners[3].dy + corners[0].dy) / 2,
    );
    // Mirror toggle: fix to visual top-left of the transformed bounds so it doesn't jump when flipped.
    handles[SelectionHandle.mirror] = bounds.topLeft + const Offset(-8, -12);
    return handles;
  }

  Map<SelectionHandle, Offset> getSelectionHandles() {
    if (_selection == null) return {};
    return _handlePositions(_selection!);
  }

  SelectionHandle hitTestSelection(
    Offset position, {
    double handleRadius = 18,
    double mirrorRadius = 26,
  }) {
    if (_selection == null) return SelectionHandle.none;
    final handles = _handlePositions(_selection!);
    if (handles.containsKey(SelectionHandle.mirror) &&
        (handles[SelectionHandle.mirror]! - position).distance <= mirrorRadius) {
      return SelectionHandle.mirror;
    }
    for (final entry in handles.entries) {
      if (entry.key == SelectionHandle.mirror) continue;
      if ((entry.value - position).distance <= handleRadius) {
        return entry.key;
      }
    }
    if (_selection!.transformedPath().contains(position)) {
      return SelectionHandle.inside;
    }
    return SelectionHandle.none;
  }

  bool shouldFinishSelection(Offset position, {double threshold = 60}) {
    if (_selection == null) return false;
    final Rect bounds = _selection!.transformedBounds();
    if (bounds.contains(position)) return false;
    final double dx = position.dx < bounds.left
        ? bounds.left - position.dx
        : position.dx - bounds.right;
    final double dy = position.dy < bounds.top
        ? bounds.top - position.dy
        : position.dy - bounds.bottom;
    final double distance = math.sqrt(math.pow(math.max(dx, 0), 2) + math.pow(math.max(dy, 0), 2));
    return distance > threshold;
  }

  void translateSelection(Offset delta) {
    if (_selection == null) return;
    _selection!.translation += delta;
    notifyListeners();
  }

  void setSelectionTransform({
    Offset? translation,
    double? scaleX,
    double? scaleY,
    double? rotation,
  }) {
    if (_selection == null) return;
    if (translation != null) _selection!.translation = translation;
    if (scaleX != null) {
      final clamped = scaleX.abs() < 0.05 ? 0.05 * scaleX.sign : scaleX;
      _selection!.scaleX = clamped;
    }
    if (scaleY != null) {
      final clamped = scaleY.abs() < 0.05 ? 0.05 * scaleY.sign : scaleY;
      _selection!.scaleY = clamped;
    }
    if (rotation != null) _selection!.rotation = rotation;
    notifyListeners();
  }

  void flipSelectionHorizontal() {
    if (_selection == null) return;
    _selection!.scaleX = -_selection!.scaleX;
    notifyListeners();
  }

  Future<void> commitSelection() async {
    if (_selection == null || _canvasSize == Size.zero) return;
    final ui.Image merged = await _renderWithSelection(_canvasSize);
    _baseImage = merged;
    _selection = null;
    _lines.clear();
    notifyListeners();
  }

  Future<ui.Image> _renderWithSelection(Size size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.srcOver);
    if (_baseImage != null) {
      canvas.drawImage(_baseImage!, Offset.zero, Paint());
    }
    _drawLines(canvas);
    if (_selection != null) {
      _paintSelection(canvas, _selection!);
    }
    final picture = recorder.endRecording();
    return picture.toImage(size.width.ceil(), size.height.ceil());
  }

  // Painting helpers shared with CustomPainter and off-screen rendering
  void _drawLines(Canvas canvas) {
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final line in _lines) {
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
}

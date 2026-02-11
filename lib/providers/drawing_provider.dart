//flpaint_プロトタイプ1.2d_筆圧第一次完成版
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as img;

import '../models/drawing.dart';

class _DrawingSnapshot {
  final List<DrawnLine> lines;
  final ui.Image? layerABaseImage;
  final ui.Image? layerBBaseImage;
  final LassoSelection? selection;

  _DrawingSnapshot({
    required this.lines,
    required this.layerABaseImage,
    required this.layerBBaseImage,
    required this.selection,
  });
}

class DrawingProvider extends ChangeNotifier {
  final List<DrawnLine> _lines = [];
  DrawnLine? _currentLine;
  Offset? _lineStartPoint;

  double _strokeWidth = 5.0;
  double _eraserWidth = 5.0;
  ToolType _tool = ToolType.pen;
  DrawingLayer _activeLayer = DrawingLayer.layerA;
  bool _isLayerAVisible = true;
  bool _isLayerBVisible = true;
  double _layerAOpacity = 1.0;
  double _layerBOpacity = 1.0;
  // Eraser passes: alternate between half-transparent and full erase per drag
  bool _nextEraserFullErase = false;
  ui.Image? _layerABaseImage;
  ui.Image? _layerBBaseImage;
  Size _canvasSize = Size.zero;

  // Lasso
  final List<Offset> _lassoPoints = [];
  bool _isDrawingLasso = false;
  LassoSelection? _selection;

  // Shapes
  Offset? _shapeStart;
  Offset? _shapeEnd;

  // Undo / Redo
  final List<_DrawingSnapshot> _undoStack = [];
  final List<_DrawingSnapshot> _redoStack = [];

  List<DrawnLine> get lines => _lines;
  List<DrawnLine> get layerALines => List<DrawnLine>.unmodifiable(
        _lines.where((line) => line.layer == DrawingLayer.layerA),
      );
  List<DrawnLine> get layerBLines => List<DrawnLine>.unmodifiable(
        _lines.where((line) => line.layer == DrawingLayer.layerB),
      );
  double get strokeWidth => _strokeWidth;
  double get eraserWidth => _eraserWidth;
  ToolType get currentTool => _tool;
  DrawingLayer get activeLayer => _activeLayer;
  bool get isLayerAVisible => _isLayerAVisible;
  bool get isLayerBVisible => _isLayerBVisible;
  double get layerAOpacity => _layerAOpacity;
  double get layerBOpacity => _layerBOpacity;
  ui.Image? get layerABaseImage => _layerABaseImage;
  ui.Image? get layerBBaseImage => _layerBBaseImage;
  List<Offset> get lassoDraft => List.unmodifiable(_lassoPoints);
  bool get isDrawingLasso => _isDrawingLasso;
  LassoSelection? get selection => _selection;
  Offset? get shapeStart => _shapeStart;
  Offset? get shapeEnd => _shapeEnd;

  // Pen dynamics constants
  static const double _jitterDistanceThreshold = 2.4;
  static const double _jitterLerpFactor = 0.25;
  static const double _regularLerpFactor = 0.45;
  static const double _tailNoiseDistance = 8.0;
  static const double _tailDirectionCosineThreshold = 0.6;
  // Distance-based taper lengths (speed-clamped)筆足
  static const double _pressureTaperInBase = 14.0;
  static const double _pressureTaperOutBase = 14.0;
  static const Size _ioCanvasSize = Size(768, 1024);
  DateTime? _lastPointTime;
  double _lastSpeed = 0.0; // px/ms for current stroke

  void setCanvasSize(Size size) {
    if (_canvasSize == size) return;
    _canvasSize = size;
  }

  void setTool(ToolType tool) {
    if (tool != ToolType.lasso) {
      _terminateLassoSession();
    }
    _tool = tool;
    if (tool != ToolType.eraser) {
      _nextEraserFullErase = false;
    }
    notifyListeners();
  }

  void setStrokeWidth(double width) {
    setPenStrokeWidth(width);
  }

  void setPenStrokeWidth(double width) {
    // End any active lasso when other controls are used
    if (_tool != ToolType.lasso) {
      _terminateLassoSession();
    }
    _strokeWidth = width.clamp(1.0, 30.0).toDouble();
    notifyListeners();
  }

  void setEraserWidth(double width) {
    if (_tool != ToolType.lasso) {
      _terminateLassoSession();
    }
    _eraserWidth = width.clamp(1.0, 30.0).toDouble();
    notifyListeners();
  }

  void setActiveLayer(DrawingLayer layer) {
    if (_activeLayer == layer) return;
    _activeLayer = layer;
    notifyListeners();
  }

  void setLayerVisibility(DrawingLayer layer, bool isVisible) {
    switch (layer) {
      case DrawingLayer.layerA:
        _isLayerAVisible = isVisible;
        break;
      case DrawingLayer.layerB:
        _isLayerBVisible = isVisible;
        break;
    }
    notifyListeners();
  }

  void setLayerOpacity(DrawingLayer layer, double opacity) {
    final clamped = opacity.clamp(0.0, 1.0).toDouble();
    switch (layer) {
      case DrawingLayer.layerA:
        _layerAOpacity = clamped;
        break;
      case DrawingLayer.layerB:
        _layerBOpacity = clamped;
        break;
    }
    notifyListeners();
  }

  Future<void> importImageFromDialog() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Image',
          extensions: ['png', 'jpg', 'jpeg'],
        ),
      ],
    );
    if (file == null) return;
    final Uint8List bytes = await file.readAsBytes();
    if (bytes.isEmpty) return;

    if (_selection != null &&
        _selection!.layer == _activeLayer &&
        _canvasSize != Size.zero) {
      await commitSelection();
    }

    _saveState();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    codec.dispose();

    final ui.Image fitted = await _fitImportedImageToCanvas(
      frame.image,
      _ioCanvasSize,
    );
    final ui.Image merged = await _mergeImageIntoLayerBase(
      _activeLayer,
      fitted,
      _ioCanvasSize,
    );
    _setLayerBaseImage(_activeLayer, merged);
    notifyListeners();
  }

  Future<void> exportImageFromDialog() async {
    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: 'flpaint.png',
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'PNG',
          extensions: ['png'],
        ),
        XTypeGroup(
          label: 'JPEG',
          extensions: ['jpg', 'jpeg'],
        ),
      ],
    );
    if (location == null) return;
    final String savePath = _normalizeExportPath(location.path);
    final String lower = savePath.toLowerCase();
    final bool exportJpeg = lower.endsWith('.jpg') || lower.endsWith('.jpeg');

    final ui.Image merged = await _renderExportImage(_ioCanvasSize);
    final Uint8List? encoded = await _encodeExportImage(
      merged,
      exportJpeg: exportJpeg,
    );
    if (encoded == null) return;
    await File(savePath).writeAsBytes(encoded, flush: true);
  }

  Future<ui.Image> _fitImportedImageToCanvas(ui.Image source, Size canvasSize) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);

    final double srcW = source.width.toDouble();
    final double srcH = source.height.toDouble();
    final double scale = math.min(
      1.0,
      math.min(canvasSize.width / srcW, canvasSize.height / srcH),
    );
    final Rect srcRect = Rect.fromLTWH(0, 0, srcW, srcH);
    final Rect dstRect = Rect.fromLTWH(0, 0, srcW * scale, srcH * scale);
    canvas.drawImageRect(source, srcRect, dstRect, Paint());

    final picture = recorder.endRecording();
    return picture.toImage(canvasSize.width.ceil(), canvasSize.height.ceil());
  }

  Future<ui.Image> _mergeImageIntoLayerBase(
    DrawingLayer layer,
    ui.Image importImage,
    Size canvasSize,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);
    final layerBase = _getLayerBaseImage(layer);
    if (layerBase != null) {
      canvas.drawImage(layerBase, Offset.zero, Paint());
    }
    canvas.drawImage(importImage, Offset.zero, Paint());
    final picture = recorder.endRecording();
    return picture.toImage(canvasSize.width.ceil(), canvasSize.height.ceil());
  }

  Future<ui.Image> _renderExportImage(Size size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);

    if (_isLayerAVisible && _layerAOpacity > 0) {
      _paintLayerCompositeForExport(
        canvas,
        size,
        DrawingLayer.layerA,
        _layerAOpacity,
      );
    }
    if (_isLayerBVisible && _layerBOpacity > 0) {
      _paintLayerCompositeForExport(
        canvas,
        size,
        DrawingLayer.layerB,
        _layerBOpacity,
      );
    }

    final picture = recorder.endRecording();
    return picture.toImage(size.width.ceil(), size.height.ceil());
  }

  void _paintLayerCompositeForExport(
    Canvas canvas,
    Size size,
    DrawingLayer layer,
    double opacity,
  ) {
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );
    final layerBase = _getLayerBaseImage(layer);
    if (layerBase != null) {
      canvas.drawImage(layerBase, Offset.zero, Paint());
    }
    _drawLines(canvas, size, layer: layer);
    if (_selection != null && _selection!.layer == layer) {
      _paintSelection(canvas, _selection!);
    }
    canvas.restore();
  }

  Future<Uint8List?> _encodeExportImage(
    ui.Image image, {
    required bool exportJpeg,
  }) async {
    if (!exportJpeg) {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    }

    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final converted = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: data.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    final jpegBytes = img.encodeJpg(converted, quality: 95);
    return Uint8List.fromList(jpegBytes);
  }

  String _normalizeExportPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg')) {
      return path;
    }
    return '$path.png';
  }

  void clear() {
    _lines.clear();
    _currentLine = null;
    _lineStartPoint = null;
    _lassoPoints.clear();
    _isDrawingLasso = false;
    _selection = null;
    _layerABaseImage = null;
    _layerBBaseImage = null;
    _shapeStart = null;
    _shapeEnd = null;
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  ui.Image? _getLayerBaseImage(DrawingLayer layer) {
    return layer == DrawingLayer.layerA ? _layerABaseImage : _layerBBaseImage;
  }

  void _setLayerBaseImage(DrawingLayer layer, ui.Image? image) {
    if (layer == DrawingLayer.layerA) {
      _layerABaseImage = image;
    } else {
      _layerBBaseImage = image;
    }
  }

  void _clearLayerLines(DrawingLayer layer) {
    _lines.removeWhere((line) => line.layer == layer);
  }
  void _terminateLassoSession() {
    if (_isDrawingLasso) {
      _lassoPoints.clear();
      _isDrawingLasso = false;
    }
    if (_selection != null) {
      if (_canvasSize != Size.zero) {
        unawaited(commitSelection());
      } else {
        _selection = null;
        notifyListeners();
      }
    }
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

  void _applyPressureTailTaper(DrawnLine line) {
  final pts = line.points;
  if (pts.length < 3) return;

  final cumulative = <double>[0];
  for (int i = 1; i < pts.length; i++) {
    cumulative.add(cumulative.last + (pts[i].offset - pts[i - 1].offset).distance);
  }

  final totalLen = cumulative.last;
  final taperOutLen = _pressureTaperOutBase; // 14.0を使用
  final taperStart = math.max(0.0, totalLen - taperOutLen);

  for (int i = 0; i < pts.length; i++) {
    final d = cumulative[i];
    if (d <= taperStart) continue;

    final t = ((totalLen - d) / taperOutLen).clamp(0.0, 1.0);
    final eased = math.pow(t, 1.2).toDouble(); // 滑らかなカーブ

    final w = math.max(1.0, pts[i].width * eased); 
    pts[i] = Point(pts[i].offset, w);
  }
}

  double _normalizedSpeed() {
    final speedNorm = (_lastSpeed * 1000) / 1200.0; // reference 1200 px/s
    return speedNorm.clamp(0.0, 2.0);
  }

  double _easeOutQuad(double t) => 1 - (1 - t) * (1 - t);

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_createSnapshot());
    _restoreSnapshot(_undoStack.removeLast());
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_createSnapshot());
    _restoreSnapshot(_redoStack.removeLast());
    notifyListeners();
  }

  void _saveState() {
    _undoStack.add(_createSnapshot());
    if (_undoStack.length > 100) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  _DrawingSnapshot _createSnapshot() {
    return _DrawingSnapshot(
      lines: List<DrawnLine>.from(_lines.map(_cloneLine)),
      layerABaseImage: _layerABaseImage,
      layerBBaseImage: _layerBBaseImage,
      selection: _cloneSelection(_selection),
    );
  }

  void _restoreSnapshot(_DrawingSnapshot snapshot) {
    _lines
      ..clear()
      ..addAll(snapshot.lines.map(_cloneLine));
    _layerABaseImage = snapshot.layerABaseImage;
    _layerBBaseImage = snapshot.layerBBaseImage;
    _selection = _cloneSelection(snapshot.selection);
  }

  DrawnLine _cloneLine(DrawnLine src) {
    return DrawnLine(
      List<Point>.from(src.points),
      color: src.color,
      width: src.width,
      tool: src.tool,
      variableWidth: src.variableWidth,
      isEraser: src.isEraser,
      eraserAlpha: src.eraserAlpha,
      isFinished: src.isFinished,
      layer: src.layer,
      shapeRect: src.shapeRect == null
          ? null
          : Rect.fromLTWH(
              src.shapeRect!.left,
              src.shapeRect!.top,
              src.shapeRect!.width,
              src.shapeRect!.height,
            ),
    );
  }

  LassoSelection? _cloneSelection(LassoSelection? src) {
    if (src == null) return null;
    final Path clonedPath = Path()..addPath(src.maskPath, Offset.zero);
    return LassoSelection(
      image: src.image,
      maskPath: clonedPath,
      layer: src.layer,
      baseRect: Rect.fromLTWH(
        src.baseRect.left,
        src.baseRect.top,
        src.baseRect.width,
        src.baseRect.height,
      ),
      translation: src.translation,
      scaleX: src.scaleX,
      scaleY: src.scaleY,
      rotation: src.rotation,
    );
  }

  void startNewLine(Offset startPoint) {
    if (_tool == ToolType.lasso) return;
    _saveState();

    if (_isShapeTool(_tool)) {
      _shapeStart = startPoint;
      _shapeEnd = startPoint;
      notifyListeners();
      return;
    }

    _lineStartPoint = startPoint;
    final bool isEraserStroke = _tool == ToolType.eraser;
    final double activeStrokeWidth =
        isEraserStroke ? _eraserWidth : _strokeWidth;
    const color = Colors.black;
    // Pressure uses pseudo-pen dynamics; others keep fixed width.
    final bool variableWidth = _tool == ToolType.pressure;
    _lastPointTime = DateTime.now();
    _lastSpeed = 0.0;
    final double eraserAlpha;
    if (isEraserStroke) {
      eraserAlpha = _nextEraserFullErase ? 1.0 : 0.5;
      _nextEraserFullErase = true; // subsequent drags erase fully
    } else {
      eraserAlpha = 1.0;
    }
    _currentLine = DrawnLine(
      [
        Point(
          startPoint,
          _tool == ToolType.pressure ? 0.01 : activeStrokeWidth,
        )
      ],
      color: color,
      width: activeStrokeWidth,
      tool: _tool,
      variableWidth: variableWidth,
      isEraser: isEraserStroke,
      eraserAlpha: eraserAlpha,
      isFinished: false,
      layer: _activeLayer,
    );
    _lines.add(_currentLine!);
    notifyListeners();
  }

  void addPoint(Offset point, Offset lastPoint) {
  if (_isShapeTool(_tool)) {
    _shapeEnd = point;
    notifyListeners();
    return;
  }

  if (_currentLine == null || _lineStartPoint == null) return;

  final currentPoints = _currentLine!.points;
  final lastStored = currentPoints.last;
  final distanceToLast = (point - lastStored.offset).distance;

  // ボコボコ防止（0.5px以下の微細な動きを無視）
  if (distanceToLast < 0.5) return; 

  final smoothedOffset = _smoothOffset(point);

  // 速度計算
  final now = DateTime.now();
  if (_lastPointTime != null) {
    final dtMs = now.difference(_lastPointTime!).inMicroseconds / 1000.0;
    if (dtMs > 0) _lastSpeed = distanceToLast / dtMs;
  }
  _lastPointTime = now;

  double width = _currentLine!.width;
  if (_currentLine!.variableWidth) {
    final speedFactor = (1.0 - 0.1 * _normalizedSpeed()).clamp(0.8, 1.0);
    final baseWidth = _currentLine!.width * speedFactor;

    final distanceFromStart = (smoothedOffset - _lineStartPoint!).distance;

    // 入りの処理（7.0pxかけて1pxから太くする）
    if (distanceFromStart <= _pressureTaperInBase) {
      final t = (distanceFromStart / _pressureTaperInBase).clamp(0.0, 1.0);
      final eased = math.pow(t, 1.5).toDouble(); 
      width = math.max(1.0, baseWidth * eased);
    } else {
      width = baseWidth;
    }
  }

  currentPoints.add(Point(smoothedOffset, width));
  notifyListeners();
}

  void endLine() {
    if (_isShapeTool(_tool)) {
      if (_shapeStart != null && _shapeEnd != null) {
        _finalizeShape(_shapeStart!, _shapeEnd!);
      }
      _shapeStart = null;
      _shapeEnd = null;
      notifyListeners();
      return;
    }

    if (_currentLine == null) return;

    if (_currentLine!.variableWidth) {
      _trimTailNoise();
      _applyPressureTailTaper(_currentLine!);
    }

    _currentLine!.isFinished = true;
    _currentLine = null;
    _lineStartPoint = null;
    notifyListeners();
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

  void _finalizeShape(Offset start, Offset end) {
    final left = math.min(start.dx, end.dx);
    final right = math.max(start.dx, end.dx);
    final top = math.min(start.dy, end.dy);
    final bottom = math.max(start.dy, end.dy);
    final rect = Rect.fromLTRB(left, top, right, bottom);

    switch (_tool) {
      case ToolType.rect:
        _addRect(rect, fill: false);
        break;
      case ToolType.fillRect:
        _addRect(rect, fill: true);
        break;
      case ToolType.circle:
        _addCircle(rect, fill: false);
        break;
      case ToolType.fillCircle:
        _addCircle(rect, fill: true);
        break;
      case ToolType.line:
        _addStraightLine(start, end);
        break;
      case ToolType.dot30:
      case ToolType.dot60:
      case ToolType.dot80:
        _addDotPattern(rect, density: _tool == ToolType.dot30 ? 0.3 : _tool == ToolType.dot60 ? 0.6 : 0.8);
        break;
      default:
        break;
    }
  }

  void _addRect(Rect rect, {required bool fill}) {
    _lines.add(DrawnLine(
      const [],
      color: Colors.black,
      width: _strokeWidth,
      tool: fill ? ToolType.fillRect : ToolType.rect,
      variableWidth: false,
      isEraser: false,
      isFinished: true,
      layer: _activeLayer,
      shapeRect: rect,
    ));
  }

  void _addCircle(Rect rect, {required bool fill}) {
    _lines.add(DrawnLine(
      const [],
      color: Colors.black,
      width: _strokeWidth,
      tool: fill ? ToolType.fillCircle : ToolType.circle,
      variableWidth: false,
      isEraser: false,
      isFinished: true,
      layer: _activeLayer,
      shapeRect: rect,
    ));
  }

  void _addStraightLine(Offset start, Offset end) {
    _lines.add(DrawnLine(
      [Point(start, _strokeWidth), Point(end, _strokeWidth)],
      color: Colors.black,
      width: _strokeWidth,
      tool: ToolType.line,
      variableWidth: false,
      isEraser: false,
      isFinished: true,
      layer: _activeLayer,
    ));
  }

  void _addDotPattern(Rect rect, {required double density}) {
    final points = <Point>[];
    const spacing = 12.0;
    final rnd = math.Random();
    for (double y = rect.top; y <= rect.bottom; y += spacing) {
      for (double x = rect.left; x <= rect.right; x += spacing) {
        if (rnd.nextDouble() <= density) {
          points.add(Point(Offset(x, y), _strokeWidth));
        }
      }
    }
    _lines.add(DrawnLine(
      points,
      color: Colors.black,
      width: _strokeWidth,
      tool: ToolType.dot30, // density encoded in points; tool not critical
      variableWidth: false,
      isEraser: false,
      isFinished: true,
      layer: _activeLayer,
    ));
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

    _saveState();
    final path = Path()..addPolygon(List.of(_lassoPoints), true);
    final bounds = path.getBounds();
    _lassoPoints.clear();
    _isDrawingLasso = false;

    if (bounds.width < 2 || bounds.height < 2) {
      notifyListeners();
      return;
    }

    final DrawingLayer layer = _activeLayer;
    final ui.Image source = await _renderLayerBaseAndLines(size, layer);
    final ui.Image selectionImage = await _extractSelection(source, path, bounds);
    final ui.Image background = await _eraseSelection(source, path, size);

    _setLayerBaseImage(layer, background);
    _clearLayerLines(layer);
    _selection = LassoSelection(
      image: selectionImage,
      maskPath: path,
      layer: layer,
      baseRect: bounds,
    );
    notifyListeners();
  }

  Future<ui.Image> _renderLayerBaseAndLines(Size size, DrawingLayer layer) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);
    final layerBaseImage = _getLayerBaseImage(layer);
    if (layerBaseImage != null) {
      canvas.drawImage(layerBaseImage, Offset.zero, Paint());
    }
    _drawLines(canvas, size, layer: layer);
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

  void beginSelectionInteraction() {
    if (_selection == null) return;
    _saveState();
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
    _saveState();
    _selection!.scaleX = -_selection!.scaleX;
    notifyListeners();
  }

  Future<void> commitSelection() async {
    if (_selection == null || _canvasSize == Size.zero) return;
    _saveState();
    final DrawingLayer layer = _selection!.layer;
    final ui.Image merged = await _renderLayerWithSelection(_canvasSize, layer);
    _setLayerBaseImage(layer, merged);
    _selection = null;
    _clearLayerLines(layer);
    notifyListeners();
  }

  Future<ui.Image> _renderLayerWithSelection(Size size, DrawingLayer layer) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);
    final layerBaseImage = _getLayerBaseImage(layer);
    if (layerBaseImage != null) {
      canvas.drawImage(layerBaseImage, Offset.zero, Paint());
    }
    _drawLines(canvas, size, layer: layer);
    if (_selection != null && _selection!.layer == layer) {
      _paintSelection(canvas, _selection!);
    }
    final picture = recorder.endRecording();
    return picture.toImage(size.width.ceil(), size.height.ceil());
  }

  // Painting helpers shared with CustomPainter and off-screen rendering
  void _drawLines(Canvas canvas, Size size, {DrawingLayer? layer}) {
    final paint = Paint()
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final line in _lines) {
      if (layer != null && line.layer != layer) continue;
      paint
        ..color = line.color.withValues(alpha: line.eraserAlpha)
        ..blendMode = line.isEraser ? BlendMode.dstOut : BlendMode.srcOver
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

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
        final dx = 0.5 *
            ((2 * p1.offset.dx) +
                (-p0.offset.dx + p2.offset.dx) * t +
                (2 * p0.offset.dx - 5 * p1.offset.dx + 4 * p2.offset.dx - p3.offset.dx) * t2 +
                (-p0.offset.dx + 3 * p1.offset.dx - 3 * p2.offset.dx + p3.offset.dx) * t3);
        final dy = 0.5 *
            ((2 * p1.offset.dy) +
                (-p0.offset.dy + p2.offset.dy) * t +
                (2 * p0.offset.dy - 5 * p1.offset.dy + 4 * p2.offset.dy - p3.offset.dy) * t2 +
                (-p0.offset.dy + 3 * p1.offset.dy - 3 * p2.offset.dy + p3.offset.dy) * t3);
        final width = ui.lerpDouble(p1.width, p2.width, t)!;
        dense.add(Point(Offset(dx, dy), width));
      }
    }
    dense.add(pts.last);
    return dense;
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

}

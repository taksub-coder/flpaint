//flpaint_プロトタイプ1.2d_筆圧第一次完成版
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:image/image.dart' as img;

import '../models/drawing.dart';

class _DrawingSnapshot {
  final List<DrawnLine> lines;
  final ui.Image? layerABaseImage;
  final ui.Image? layerBBaseImage;
  final LassoSelection? selection;
  final bool selectionMasksSource;
  final bool selectionHandlesFilled;
  final bool selectionMergeToActiveLayer;

  _DrawingSnapshot({
    required this.lines,
    required this.layerABaseImage,
    required this.layerBBaseImage,
    required this.selection,
    required this.selectionMasksSource,
    required this.selectionHandlesFilled,
    required this.selectionMergeToActiveLayer,
  });
}

class _VerticalTextColumn {
  final List<TextPainter> glyphPainters;
  final List<double> glyphWidths;
  final List<_VerticalGlyphKind> glyphKinds;
  final List<Offset> glyphOffsets;
  final double width;
  final double height;
  final double topPadding;

  _VerticalTextColumn({
    required this.glyphPainters,
    required this.glyphWidths,
    required this.glyphKinds,
    required this.glyphOffsets,
    required this.width,
    required this.height,
    required this.topPadding,
  });
}

enum _VerticalGlyphKind {
  normal,
  special,
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
  ui.ImageShader? _tone30Shader;
  ui.ImageShader? _tone60Shader;
  ui.ImageShader? _tone80Shader;

  // Lasso
  final List<Offset> _lassoPoints = [];
  bool _isDrawingLasso = false;
  LassoSelection? _selection;
  bool _selectionMasksSource = true;
  bool _selectionHandlesFilled = false;
  bool _selectionMergeToActiveLayer = false;
  ui.Image? _clipboardImage;

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
  ui.ImageShader? get tone30Shader => _tone30Shader;
  ui.ImageShader? get tone60Shader => _tone60Shader;
  ui.ImageShader? get tone80Shader => _tone80Shader;
  List<Offset> get lassoDraft => List.unmodifiable(_lassoPoints);
  bool get isDrawingLasso => _isDrawingLasso;
  LassoSelection? get selection => _selection;
  bool get selectionMasksSource => _selectionMasksSource;
  bool get selectionHandlesFilled => _selectionHandlesFilled;
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
  static const double _lassoSelectionSuperSample = 2.0;
  static const int _toneTileSize = 2;
  static const int _toneSuperSampleScale = 8;
  static const Set<String> _verticalSpecialGlyphs = <String>{
    'っ',
    'ゃ',
    'ゅ',
    'ょ',
    'ぁ',
    'ぃ',
    'ぅ',
    'ぇ',
    'ぉ',
    'ゎ',
    'ッ',
    'ャ',
    'ュ',
    'ョ',
    'ァ',
    'ィ',
    'ゥ',
    'ェ',
    'ォ',
    'ヮ',
    'ヵ',
    'ヶ',
    '、',
    '。',
    '，',
    '．',
    '・',
    '“',
    '”',
    '！',
    '？',
  };
  static final Float64List _toneShaderMatrixRotated = (() {
    final c = math.cos(math.pi / 4);
    final s = math.sin(math.pi / 4);
    return Float64List.fromList(
      <double>[
        c,
        s,
        0,
        0,
        -s,
        c,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
      ],
    );
  })();
  DateTime? _lastPointTime;
  double _lastSpeed = 0.0; // px/ms for current stroke

  DrawingProvider() {
    _initializeToneShaders();
  }

  void setCanvasSize(Size size) {
    if (_canvasSize == size) return;
    _canvasSize = size;
  }

  Future<void> _initializeToneShaders() async {
    final tone30Image = await _createToneTileImage(
      blackPixels: 1,
    );
    final tone60Image = await _createToneTileImage(
      blackPixels: 2,
    );
    final tone80Image = await _createToneTileImage(
      blackPixels: 3,
    );

    _tone30Shader = ui.ImageShader(
      tone30Image,
      TileMode.repeated,
      TileMode.repeated,
      _toneShaderMatrixRotated,
    );
    _tone60Shader = ui.ImageShader(
      tone60Image,
      TileMode.repeated,
      TileMode.repeated,
      _toneShaderMatrixRotated,
    );
    _tone80Shader = ui.ImageShader(
      tone80Image,
      TileMode.repeated,
      TileMode.repeated,
      _toneShaderMatrixRotated,
    );
    notifyListeners();
  }

  Future<ui.Image> _createToneTileImage({
    required int blackPixels,
  }) async {
    final int sourceSize = _toneTileSize * _toneSuperSampleScale;
    final double sourceScale = _toneSuperSampleScale.toDouble();
    final sourceRecorder = ui.PictureRecorder();
    final sourceCanvas = Canvas(sourceRecorder);
    sourceCanvas.drawColor(Colors.transparent, BlendMode.src);
    final dotPaint = Paint()
      ..color = const Color(0xF2010101)
      ..isAntiAlias = false;

    final pixels = <Offset>[];
    if (blackPixels >= 1) {
      pixels.add(const Offset(0, 0)); // 30% base
    }
    if (blackPixels >= 2) {
      pixels.add(const Offset(1, 1)); // 60% checker
    }
    if (blackPixels >= 3) {
      pixels.add(const Offset(1, 0)); // 80%
    }

    for (final pixel in pixels) {
      sourceCanvas.drawRect(
        Rect.fromLTWH(
          pixel.dx * sourceScale,
          pixel.dy * sourceScale,
          sourceScale,
          sourceScale,
        ),
        dotPaint,
      );
    }

    final sourcePicture = sourceRecorder.endRecording();
    final sourceImage = await sourcePicture.toImage(sourceSize, sourceSize);

    final downsampleRecorder = ui.PictureRecorder();
    final downsampleCanvas = Canvas(downsampleRecorder);
    downsampleCanvas.drawColor(Colors.transparent, BlendMode.src);
    downsampleCanvas.drawImageRect(
      sourceImage,
      Rect.fromLTWH(0, 0, sourceSize.toDouble(), sourceSize.toDouble()),
      Rect.fromLTWH(0, 0, _toneTileSize.toDouble(), _toneTileSize.toDouble()),
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high,
    );
    final downsamplePicture = downsampleRecorder.endRecording();
    return downsamplePicture.toImage(_toneTileSize, _toneTileSize);
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

  Future<void> exportImageFromDialog({BuildContext? context}) async {
    if (Platform.isAndroid) {
      final bool exportJpeg = await _selectAndroidExportIsJpeg(context);
      final ui.Image merged = await _renderExportImage(_ioCanvasSize);
      final Uint8List? encoded = await _encodeExportImage(
        merged,
        exportJpeg: exportJpeg,
      );
      if (encoded == null) return;
      await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          data: encoded,
          fileName: _buildTimestampedExportFileName(exportJpeg: exportJpeg),
          mimeTypesFilter: [
            exportJpeg ? 'image/jpeg' : 'image/png',
          ],
        ),
      );
      return;
    }

    final ui.Image merged = await _renderExportImage(_ioCanvasSize);

    if (Platform.isWindows) {
      if (context != null && !context.mounted) return;
      final bool? exportJpeg = await _selectWindowsExportIsJpeg(context);
      if (exportJpeg == null) return;
      final FileSaveLocation? location = await getSaveLocation(
        suggestedName: _buildTimestampedExportFileName(exportJpeg: exportJpeg),
        acceptedTypeGroups: [
          exportJpeg
              ? const XTypeGroup(
                  label: 'JPEG',
                  extensions: ['jpg', 'jpeg'],
                )
              : const XTypeGroup(
                  label: 'PNG',
                  extensions: ['png'],
                ),
        ],
      );
      if (location == null) return;
      final String savePath = _normalizeExportPathForFormat(
        location.path,
        exportJpeg: exportJpeg,
      );
      final Uint8List? encoded = await _encodeExportImage(
        merged,
        exportJpeg: exportJpeg,
      );
      if (encoded == null) return;
      await File(savePath).writeAsBytes(encoded, flush: true);
      return;
    }

    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: _buildTimestampedExportFileName(exportJpeg: false),
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

    final Uint8List? encoded = await _encodeExportImage(
      merged,
      exportJpeg: exportJpeg,
    );
    if (encoded == null) return;
    await File(savePath).writeAsBytes(encoded, flush: true);
  }

  Future<bool> _selectAndroidExportIsJpeg(BuildContext? context) async {
    if (context == null) return false;
    final bool? exportJpeg = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Export format'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('PNG'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('JPG'),
            ),
          ],
        );
      },
    );
    return exportJpeg ?? false;
  }

  Future<bool?> _selectWindowsExportIsJpeg(BuildContext? context) async {
    if (context == null) return false;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Export format'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('PNG'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('JPG'),
            ),
          ],
        );
      },
    );
  }

  Future<ui.Image> _fitImportedImageToCanvas(
      ui.Image source, Size canvasSize) async {
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
      if (_selectionMasksSource) {
        _clearSelectionArea(canvas, _selection!);
      }
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
    final whiteBackground = img.Image(width: image.width, height: image.height);
    img.fill(whiteBackground, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(whiteBackground, converted);
    final jpegBytes = img.encodeJpg(whiteBackground, quality: 95);
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

  String _normalizeExportPathForFormat(
    String path, {
    required bool exportJpeg,
  }) {
    final String extension = exportJpeg ? '.jpg' : '.png';
    final String lower = path.toLowerCase();
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg')) {
      return _replacePathExtension(path, extension);
    }
    return '$path$extension';
  }

  String _replacePathExtension(String path, String extension) {
    final int lastSlash =
        math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
    final int lastDot = path.lastIndexOf('.');
    if (lastDot <= lastSlash) {
      return '$path$extension';
    }
    return '${path.substring(0, lastDot)}$extension';
  }

  String _buildTimestampedExportFileName({required bool exportJpeg}) {
    final now = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final String timestamp =
        '${now.year}${twoDigits(now.month)}${twoDigits(now.day)}_${twoDigits(now.hour)}${twoDigits(now.minute)}${twoDigits(now.second)}';
    final String extension = exportJpeg ? 'jpg' : 'png';
    return '$timestamp.$extension';
  }

  void clear() {
    _lines.clear();
    _currentLine = null;
    _lineStartPoint = null;
    _lassoPoints.clear();
    _isDrawingLasso = false;
    _resetSelectionState();
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

  void _resetSelectionState() {
    _selection = null;
    _selectionMasksSource = true;
    _selectionHandlesFilled = false;
    _selectionMergeToActiveLayer = false;
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
        _resetSelectionState();
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
      cumulative
          .add(cumulative.last + (pts[i].offset - pts[i - 1].offset).distance);
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

  Color _strokeColorForTool(ToolType tool) {
    switch (tool) {
      default:
        return Colors.black;
    }
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
      selectionMasksSource: _selectionMasksSource,
      selectionHandlesFilled: _selectionHandlesFilled,
      selectionMergeToActiveLayer: _selectionMergeToActiveLayer,
    );
  }

  void _restoreSnapshot(_DrawingSnapshot snapshot) {
    _lines
      ..clear()
      ..addAll(snapshot.lines.map(_cloneLine));
    _layerABaseImage = snapshot.layerABaseImage;
    _layerBBaseImage = snapshot.layerBBaseImage;
    _selection = _cloneSelection(snapshot.selection);
    _selectionMasksSource = snapshot.selectionMasksSource;
    _selectionHandlesFilled = snapshot.selectionHandlesFilled;
    _selectionMergeToActiveLayer = snapshot.selectionMergeToActiveLayer;
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
    final color = _strokeColorForTool(_tool);
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

  void cancelCurrentLine() {
    if (_isShapeTool(_tool)) {
      if (_shapeStart != null || _shapeEnd != null) {
        _shapeStart = null;
        _shapeEnd = null;
        notifyListeners();
      }
      return;
    }

    if (_currentLine == null) return;
    _lines.remove(_currentLine);
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
        _addDotPattern(rect,
            density: _tool == ToolType.dot30
                ? 0.3
                : _tool == ToolType.dot60
                    ? 0.6
                    : 0.8);
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
    final ui.Image selectionImage = await _extractSelection(
      size,
      layer,
      path,
      bounds,
    );
    _selection = LassoSelection(
      image: selectionImage,
      maskPath: path,
      layer: layer,
      baseRect: bounds,
    );
    _selectionMasksSource = true;
    _selectionHandlesFilled = false;
    _selectionMergeToActiveLayer = false;
    notifyListeners();
  }

  Future<ui.Image> _extractSelection(
    Size canvasSize,
    DrawingLayer layer,
    Path path,
    Rect bounds,
  ) async {
    const double sampleScale = _lassoSelectionSuperSample;
    final int sampledWidth = math.max(
      1,
      (bounds.width * sampleScale).ceil(),
    );
    final int sampledHeight = math.max(
      1,
      (bounds.height * sampleScale).ceil(),
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(sampleScale, sampleScale);
    canvas.translate(-bounds.left, -bounds.top);
    canvas.clipPath(path);
    final layerBaseImage = _getLayerBaseImage(layer);
    if (layerBaseImage != null) {
      canvas.drawImage(layerBaseImage, Offset.zero, Paint());
    }
    _drawLines(canvas, canvasSize, layer: layer);
    final picture = recorder.endRecording();

    final ui.Image sampled = await picture.toImage(sampledWidth, sampledHeight);
    if (sampleScale == 1.0) {
      return sampled;
    }

    final downsampleRecorder = ui.PictureRecorder();
    final downsampleCanvas = Canvas(downsampleRecorder);
    downsampleCanvas.drawColor(Colors.transparent, BlendMode.src);
    downsampleCanvas.drawImageRect(
      sampled,
      Rect.fromLTWH(0, 0, sampled.width.toDouble(), sampled.height.toDouble()),
      Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high,
    );
    final downsamplePicture = downsampleRecorder.endRecording();
    return downsamplePicture.toImage(bounds.width.ceil(), bounds.height.ceil());
  }

  Future<void> cutSelectionToClipboard() async {
    if (_selection == null || _canvasSize == Size.zero) return;
    _saveState();
    final LassoSelection selection = _selection!;
    _clipboardImage = selection.image;

    final ui.Image cutLayer = await _renderLayerWithClearedSelection(
      _canvasSize,
      selection.layer,
      selection,
    );
    _setLayerBaseImage(selection.layer, cutLayer);
    _clearLayerLines(selection.layer);
    _resetSelectionState();
    notifyListeners();
  }

  Future<void> copyPasteSelection() async {
    if (_selection != null) {
      _saveState();
      _clipboardImage = _selection!.image;
      _selectionMasksSource = false;
      _selectionHandlesFilled = true;
      _selectionMergeToActiveLayer = true;
      notifyListeners();
      return;
    }

    if (_clipboardImage == null) return;
    _saveState();
    final ui.Image image = _clipboardImage!;
    final Size canvasSize =
        _canvasSize == Size.zero ? _ioCanvasSize : _canvasSize;
    final Rect baseRect = Rect.fromLTWH(
      (canvasSize.width - image.width.toDouble()) / 2,
      (canvasSize.height - image.height.toDouble()) / 2,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    _selection = LassoSelection(
      image: image,
      maskPath: Path()..addRect(baseRect),
      layer: _activeLayer,
      baseRect: baseRect,
    );
    _selectionMasksSource = false;
    _selectionHandlesFilled = true;
    _selectionMergeToActiveLayer = true;
    _tool = ToolType.lasso;
    notifyListeners();
  }

  Future<void> addTextToActiveLayer({
    required String text,
    BuildContext? context,
    String? fontFamily,
    double fontSize = 32,
    bool vertical = false,
  }) async {
    if (text.trim().isEmpty) return;

    if (_selection != null && _canvasSize != Size.zero) {
      await commitSelection();
    }
    if (context != null && !context.mounted) return;

    _saveState();
    final Size canvasSize =
        _canvasSize == Size.zero ? _ioCanvasSize : _canvasSize;
    final String normalizedText = text.replaceAll('\r\n', '\n');
    final ui.Image textImage = await _buildTextSelectionImage(
      text: normalizedText,
      context: context,
      fontFamily: fontFamily,
      fontSize: fontSize,
      vertical: vertical,
      maxWidth: canvasSize.width,
    );
    final Rect baseRect = Rect.fromLTWH(
      (canvasSize.width - textImage.width.toDouble()) / 2,
      (canvasSize.height - textImage.height.toDouble()) / 2,
      textImage.width.toDouble(),
      textImage.height.toDouble(),
    );
    _selection = LassoSelection(
      image: textImage,
      maskPath: Path()..addRect(baseRect),
      layer: _activeLayer,
      baseRect: baseRect,
    );
    _selectionMasksSource = false;
    _selectionHandlesFilled = true;
    _selectionMergeToActiveLayer = true;
    _tool = ToolType.lasso;
    notifyListeners();
  }

  Future<ui.Image> _buildTextSelectionImage({
    required String text,
    required BuildContext? context,
    required String? fontFamily,
    required double fontSize,
    required bool vertical,
    required double maxWidth,
  }) async {
    return vertical
        ? _buildVerticalTextImage(
            text: text,
            fontFamily: fontFamily,
            fontSize: fontSize,
          )
        : _buildHorizontalTextImage(
            text: text,
            context: context,
            fontFamily: fontFamily,
            fontSize: fontSize,
            maxWidth: maxWidth,
          );
  }

  Future<ui.Image> _buildHorizontalTextImage({
    required String text,
    required BuildContext? context,
    required String? fontFamily,
    required double fontSize,
    required double maxWidth,
  }) async {
    if (context != null) {
      final Widget horizontalText = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Text(
          text,
          textAlign: TextAlign.center,
          softWrap: true,
          style: TextStyle(
            color: Colors.black,
            fontSize: fontSize,
            height: 1.2,
            fontFamily: fontFamily,
          ),
        ),
      );
      return _widgetToImage(
        horizontalText,
        context: context,
      );
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black,
          fontSize: fontSize,
          height: 1.2,
          fontFamily: fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: maxWidth);
    final int width = math.max(1, textPainter.width.ceil());
    final int height = math.max(1, textPainter.height.ceil());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);
    textPainter.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();
    return picture.toImage(width, height);
  }

  Future<ui.Image> _buildVerticalTextImage({
    required String text,
    required String? fontFamily,
    required double fontSize,
  }) async {
    final List<String> lines = text.split('\n');
    final List<_VerticalTextColumn> columns = <_VerticalTextColumn>[];
    // Match previous VerticalTextStyle spacing (characterSpacing: 0.10, lineSpacing: 1.05).
    const double characterSpacing = 0.10;
    const double lineSpacing = 1.05;
    final double glyphAdvance = fontSize + characterSpacing;
    const double columnGap = lineSpacing;

    for (final line in lines) {
      final List<int> runes = line.isEmpty ? <int>[0x20] : line.runes.toList();
      final List<TextPainter> glyphPainters = <TextPainter>[];
      final List<double> glyphWidths = <double>[];
      final List<_VerticalGlyphKind> glyphKinds = <_VerticalGlyphKind>[];
      final List<Offset> glyphOffsets = <Offset>[];
      double maxGlyphWidth = 0;
      double maxGlyphHeight = 0;
      double maxRightOffset = 0;
      double maxTopOffset = 0;

      for (final rune in runes) {
        final String sourceGlyph = String.fromCharCode(rune);
        final _VerticalGlyphKind glyphKind =
            _classifyVerticalGlyph(sourceGlyph);
        final Offset glyphOffset = _verticalGlyphOffset(
          sourceGlyph,
          fontSize,
          glyphKind,
        );
        final String glyph = _normalizeVerticalGlyph(sourceGlyph);
        final TextPainter glyphPainter = TextPainter(
          text: TextSpan(
            text: glyph,
            style: TextStyle(
              color: Colors.black,
              fontSize: fontSize,
              height: 1.0,
              fontFamily: fontFamily,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        )..layout();
        glyphPainters.add(glyphPainter);
        glyphWidths.add(glyphPainter.width);
        glyphKinds.add(glyphKind);
        glyphOffsets.add(glyphOffset);
        maxGlyphWidth = math.max(maxGlyphWidth, glyphPainter.width);
        maxGlyphHeight = math.max(maxGlyphHeight, glyphPainter.height);
        maxRightOffset = math.max(maxRightOffset, glyphOffset.dx);
        maxTopOffset = math.max(maxTopOffset, -glyphOffset.dy);
      }

      final double columnWidth =
          math.max(fontSize, maxGlyphWidth + maxRightOffset);
      final double columnHeight = math.max(
        fontSize,
        (glyphPainters.length - 1) * glyphAdvance +
            maxGlyphHeight +
            maxTopOffset,
      );
      columns.add(
        _VerticalTextColumn(
          glyphPainters: glyphPainters,
          glyphWidths: glyphWidths,
          glyphKinds: glyphKinds,
          glyphOffsets: glyphOffsets,
          width: columnWidth,
          height: columnHeight,
          topPadding: maxTopOffset,
        ),
      );
    }

    double totalWidth = 0;
    double totalHeight = 0;
    for (int i = 0; i < columns.length; i++) {
      totalWidth += columns[i].width;
      if (i > 0) {
        totalWidth += columnGap;
      }
      totalHeight = math.max(totalHeight, columns[i].height);
    }

    final int width = math.max(1, totalWidth.ceil());
    final int height = math.max(1, totalHeight.ceil());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);
    double rightEdge = totalWidth;
    for (final column in columns) {
      final double x = rightEdge - column.width;
      double y = (totalHeight - column.height) / 2 + column.topPadding;
      final double columnCenterX = x + column.width / 2;
      for (int i = 0; i < column.glyphPainters.length; i++) {
        final TextPainter glyphPainter = column.glyphPainters[i];
        final double glyphWidth = column.glyphWidths[i];
        final Offset glyphOffset = column.glyphOffsets[i];
        final double cellTop = y;
        double glyphX = columnCenterX - glyphWidth / 2;
        double glyphY = cellTop + (glyphAdvance - glyphPainter.height) / 2;
        glyphX += glyphOffset.dx;
        glyphY += glyphOffset.dy;
        canvas.save();
        glyphPainter.paint(canvas, Offset(glyphX, glyphY));
        canvas.restore();
        y += glyphAdvance;
      }
      rightEdge = x - columnGap;
    }

    for (final column in columns) {
      for (final glyphPainter in column.glyphPainters) {
        glyphPainter.dispose();
      }
    }

    final picture = recorder.endRecording();
    return picture.toImage(width, height);
  }

  _VerticalGlyphKind _classifyVerticalGlyph(String glyph) {
    if (_verticalSpecialGlyphs.contains(glyph)) {
      return _VerticalGlyphKind.special;
    }
    return _VerticalGlyphKind.normal;
  }

  Offset _verticalGlyphOffset(
    String glyph,
    double fontSize,
    _VerticalGlyphKind glyphKind,
  ) {
    if (glyphKind != _VerticalGlyphKind.special) {
      return Offset.zero;
    }

    double rightOffset = fontSize * 0.25;
    double upOffset = fontSize * 0.10;

    if (glyph == '。' || glyph == '．') {
      rightOffset = fontSize * 0.38;
      upOffset = fontSize * 0.25;
    } else if (glyph == '、' || glyph == '，') {
      rightOffset = fontSize * 0.20;
      upOffset = fontSize * 0.12;
    } else if (glyph == '！' || glyph == '？') {
      rightOffset = fontSize * 0.32;
      upOffset = fontSize * 0.18;
    }

    return Offset(rightOffset, -upOffset);
  }

  String _normalizeVerticalGlyph(String glyph) {
    if (glyph == 'ー' || glyph == 'ｰ') {
      return '｜';
    }
    return glyph;
  }

  Future<ui.Image> _renderLayerWithClearedSelection(
    Size size,
    DrawingLayer layer,
    LassoSelection selection,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);
    final layerBaseImage = _getLayerBaseImage(layer);
    if (layerBaseImage != null) {
      canvas.drawImage(layerBaseImage, Offset.zero, Paint());
    }
    _drawLines(canvas, size, layer: layer);
    _clearSelectionArea(canvas, selection);
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
    Offset visualTopLeft = corners.first;
    for (final corner in corners.skip(1)) {
      // Find the corner with the minimum y, breaking ties with minimum x.
      if (corner.dy < visualTopLeft.dy) {
        visualTopLeft = corner;
      } else if ((corner.dy - visualTopLeft.dy).abs() < 0.1 &&
          corner.dx < visualTopLeft.dx) {
        visualTopLeft = corner;
      }
    }
    handles[SelectionHandle.mirror] = visualTopLeft + const Offset(-8, -12);
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
    double handleRadius = 24,
    double mirrorRadius = 64,
  }) {
    if (_selection == null) return SelectionHandle.none;
    final handles = _handlePositions(_selection!);
    if (handles.containsKey(SelectionHandle.mirror) &&
        (handles[SelectionHandle.mirror]! - position).distance <=
            mirrorRadius) {
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
    final double distance =
        math.sqrt(math.pow(math.max(dx, 0), 2) + math.pow(math.max(dy, 0), 2));
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
    final LassoSelection selection = _selection!;
    final DrawingLayer layer =
        _selectionMergeToActiveLayer ? _activeLayer : selection.layer;
    final bool clearSelectionArea =
        _selectionMasksSource && selection.layer == layer;
    final ui.Image merged = await _renderLayerWithSelection(
      _canvasSize,
      layer,
      selection: selection,
      clearSelectionArea: clearSelectionArea,
    );
    _setLayerBaseImage(layer, merged);
    _clearLayerLines(layer);
    _resetSelectionState();
    notifyListeners();
  }

  Future<ui.Image> _renderLayerWithSelection(
    Size size,
    DrawingLayer layer, {
    required LassoSelection selection,
    required bool clearSelectionArea,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);
    final layerBaseImage = _getLayerBaseImage(layer);
    if (layerBaseImage != null) {
      canvas.drawImage(layerBaseImage, Offset.zero, Paint());
    }
    _drawLines(canvas, size, layer: layer);
    if (clearSelectionArea) {
      _clearSelectionArea(canvas, selection);
    }
    _paintSelection(canvas, selection);
    final picture = recorder.endRecording();
    return picture.toImage(size.width.ceil(), size.height.ceil());
  }

  // Painting helpers shared with CustomPainter and off-screen rendering
  ui.ImageShader? _toneShaderForTool(ToolType tool) {
    switch (tool) {
      case ToolType.tone30:
        return _tone30Shader;
      case ToolType.tone60:
        return _tone60Shader;
      case ToolType.tone80:
        return _tone80Shader;
      default:
        return null;
    }
  }

  void _drawLines(Canvas canvas, Size size, {DrawingLayer? layer}) {
    final paint = Paint()
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final line in _lines) {
      if (layer != null && line.layer != layer) continue;
      final toneShader = line.isEraser ? null : _toneShaderForTool(line.tool);
      paint
        ..isAntiAlias = true
        ..shader = toneShader
        ..color = (toneShader == null ? line.color : Colors.white)
            .withValues(alpha: line.eraserAlpha)
        ..blendMode = line.isEraser ? BlendMode.dstOut : BlendMode.srcOver
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..filterQuality =
            toneShader == null ? FilterQuality.low : FilterQuality.high;

      switch (line.tool) {
        case ToolType.rect:
        case ToolType.fillRect:
          if (line.shapeRect == null) continue;
          paint
            ..style = line.tool == ToolType.fillRect
                ? PaintingStyle.fill
                : PaintingStyle.stroke
            ..strokeCap = StrokeCap.butt
            ..strokeJoin = StrokeJoin.miter
            ..strokeWidth = line.width;
          canvas.drawRect(line.shapeRect!, paint);
          break;
        case ToolType.circle:
        case ToolType.fillCircle:
          if (line.shapeRect == null) continue;
          paint
            ..style = line.tool == ToolType.fillCircle
                ? PaintingStyle.fill
                : PaintingStyle.stroke
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
      path.addOval(Rect.fromCircle(
          center: points.first.offset, radius: points.first.width / 2));
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
                (2 * p0.offset.dx -
                        5 * p1.offset.dx +
                        4 * p2.offset.dx -
                        p3.offset.dx) *
                    t2 +
                (-p0.offset.dx +
                        3 * p1.offset.dx -
                        3 * p2.offset.dx +
                        p3.offset.dx) *
                    t3);
        final dy = 0.5 *
            ((2 * p1.offset.dy) +
                (-p0.offset.dy + p2.offset.dy) * t +
                (2 * p0.offset.dy -
                        5 * p1.offset.dy +
                        4 * p2.offset.dy -
                        p3.offset.dy) *
                    t2 +
                (-p0.offset.dy +
                        3 * p1.offset.dy -
                        3 * p2.offset.dy +
                        p3.offset.dy) *
                    t3);
        final width = ui.lerpDouble(p1.width, p2.width, t)!;
        dense.add(Point(Offset(dx, dy), width));
      }
    }
    dense.add(pts.last);
    return dense;
  }

  void _clearSelectionArea(Canvas canvas, LassoSelection selection) {
    canvas.drawPath(
      selection.maskPath,
      Paint()
        ..blendMode = BlendMode.clear
        ..isAntiAlias = true,
    );
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
      final filteredOffset =
          Offset.lerp(previous.offset, current.offset, factor)!;
      result.add(Point(filteredOffset, current.width));
    }
    return result;
  }
}

Future<ui.Image> _widgetToImage(
  Widget widget, {
  required BuildContext context,
  double pixelRatio = 1.0,
}) async {
  final repaintKey = GlobalKey();
  final overlay = Overlay.maybeOf(context, rootOverlay: true) ??
      Navigator.of(context, rootNavigator: true).overlay;
  if (overlay == null) {
    throw StateError('Overlay is not available for text rendering.');
  }

  final overlayEntry = OverlayEntry(
    builder: (_) => IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: repaintKey,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Material(
              type: MaterialType.transparency,
              child: widget,
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(overlayEntry);
  try {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await WidgetsBinding.instance.endOfFrame;

    final BuildContext? renderContext = repaintKey.currentContext;
    if (renderContext == null) {
      throw StateError('Failed to capture rendered widget context.');
    }
    if (!renderContext.mounted) {
      throw StateError('Rendered widget context was unmounted.');
    }
    final RenderObject? renderObject = renderContext.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('Rendered widget is not a RepaintBoundary.');
    }

    return renderObject.toImage(pixelRatio: pixelRatio);
  } finally {
    overlayEntry.remove();
  }
}

//flpaint_プロトタイプ1.6_文字入力第２調整版
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
import 'package:path_provider/path_provider.dart';

import '../models/drawing.dart';
import '../painting/layer_composite_painter.dart';

class _DrawingSnapshot {
  final List<DrawnLine> lines;
  final List<LayerPlacement> placements;
  final int nextSequence;
  final ui.Image? layerABaseImage;
  final ui.Image? layerBBaseImage;
  final ui.Image? layerCBaseImage;
  final LassoSelection? selection;
  final bool selectionMasksSource;
  final bool selectionHandlesFilled;
  final bool selectionMergeToActiveLayer;

  _DrawingSnapshot({
    required this.lines,
    required this.placements,
    required this.nextSequence,
    required this.layerABaseImage,
    required this.layerBBaseImage,
    required this.layerCBaseImage,
    required this.selection,
    required this.selectionMasksSource,
    required this.selectionHandlesFilled,
    required this.selectionMergeToActiveLayer,
  });
}

class _VerticalTextColumn {
  final List<TextPainter> glyphPainters;
  final List<double> glyphRenderWidths;
  final List<double> glyphRenderHeights;
  final List<_VerticalGlyphKind> glyphKinds;
  final List<Offset> glyphOffsets;
  final List<double> glyphRotations;
  final double width;
  final double height;
  final double topPadding;

  _VerticalTextColumn({
    required this.glyphPainters,
    required this.glyphRenderWidths,
    required this.glyphRenderHeights,
    required this.glyphKinds,
    required this.glyphOffsets,
    required this.glyphRotations,
    required this.width,
    required this.height,
    required this.topPadding,
  });
}

class LayerBackupSet {
  final String id;
  final bool isAutosave;
  final DateTime savedAt;
  final String displayLabel;
  final String layerAPath;
  final String layerBPath;
  final String layerCPath;

  LayerBackupSet({
    required this.id,
    required this.isAutosave,
    required this.savedAt,
    required this.displayLabel,
    required this.layerAPath,
    required this.layerBPath,
    required this.layerCPath,
  });
}

enum _VerticalGlyphKind {
  normal,
  special,
}

/// Internal clipboard for vector lasso copy (paths stay lossless until cut rasterizes).
class _ClipboardVectorSpec {
  final Path maskPathCanvas;
  final Rect boundsAtCopy;
  final DrawingLayer layer;
  final int maxContentSequence;

  _ClipboardVectorSpec({
    required Path maskPathSource,
    required this.boundsAtCopy,
    required this.layer,
    required this.maxContentSequence,
  }) : maskPathCanvas = Path()..addPath(maskPathSource, Offset.zero);
}

class DrawingProvider extends ChangeNotifier {
  final List<DrawnLine> _lines = [];
  final List<LayerPlacement> _placements = [];
  int _nextSequence = 1;
  DrawnLine? _currentLine;
  Offset? _lineStartPoint;

  double _strokeWidth = 5.0;
  double _eraserWidth = 5.0;
  ToolType _tool = ToolType.pen;
  DrawingLayer _activeLayer = DrawingLayer.layerA;
  bool _isLayerAVisible = true;
  bool _isLayerBVisible = true;
  bool _isLayerCVisible = true;
  double _layerAOpacity = 1.0;
  double _layerBOpacity = 1.0;
  double _layerCOpacity = 1.0;
  // Eraser passes: alternate between half-transparent and full erase per drag
  bool _nextEraserFullErase = false;
  ui.Image? _layerABaseImage;
  ui.Image? _layerBBaseImage;
  ui.Image? _layerCBaseImage;
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
  _ClipboardVectorSpec? _clipboardVector;

  // Shapes
  Offset? _shapeStart;
  Offset? _shapeEnd;

  // Undo / Redo
  final List<_DrawingSnapshot> _undoStack = [];
  final List<_DrawingSnapshot> _redoStack = [];
  Directory? _manualBackupDirectory;
  Directory? _autosaveBackupDirectory;
  bool _backupDirectoriesReady = false;
  Timer? _autosaveTimer;
  bool _backupBusy = false;

  List<DrawnLine> get lines => _lines;
  List<DrawnLine> get layerALines => List<DrawnLine>.unmodifiable(
        _lines.where((line) => line.layer == DrawingLayer.layerA),
      );
  List<DrawnLine> get layerBLines => List<DrawnLine>.unmodifiable(
        _lines.where((line) => line.layer == DrawingLayer.layerB),
      );
  List<DrawnLine> get layerCLines => List<DrawnLine>.unmodifiable(
        _lines.where((line) => line.layer == DrawingLayer.layerC),
      );
  List<LayerPlacement> get placements =>
      List<LayerPlacement>.unmodifiable(_placements);
  double get strokeWidth => _strokeWidth;
  double get eraserWidth => _eraserWidth;
  ToolType get currentTool => _tool;
  DrawingLayer get activeLayer => _activeLayer;
  bool get isLayerAVisible => _isLayerAVisible;
  bool get isLayerBVisible => _isLayerBVisible;
  bool get isLayerCVisible => _isLayerCVisible;
  double get layerAOpacity => _layerAOpacity;
  double get layerBOpacity => _layerBOpacity;
  double get layerCOpacity => _layerCOpacity;
  ui.Image? get layerABaseImage => _layerABaseImage;
  ui.Image? get layerBBaseImage => _layerBBaseImage;
  ui.Image? get layerCBaseImage => _layerCBaseImage;
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
  static const Duration _autosaveInterval = Duration(minutes: 5);
  static const List<DrawingLayer> _backupLayers = <DrawingLayer>[
    DrawingLayer.layerA,
    DrawingLayer.layerB,
    DrawingLayer.layerC,
  ];

  /// Tone tile settings.
  static const int _toneTileSize = 2;
  static const int _toneSuperSampleScale = 8;
  static const double _horizontalTextLineHeight = 1.2;
  static const double _textSelectionPaddingLines = 1.0;
  static const double _verticalPunctuationNudgePoints = 3.0;
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
    '〜',
    '～',
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
    unawaited(_initializeBackupSystem());
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    super.dispose();
  }

  void setCanvasSize(Size size) {
    if (_canvasSize == size) return;
    _canvasSize = size;
  }

  Future<void> _initializeBackupSystem() async {
    await _ensureBackupDirectories();
    _startAutosaveTimer();
  }

  Future<void> _ensureBackupDirectories() async {
    if (_backupDirectoriesReady &&
        _manualBackupDirectory != null &&
        _autosaveBackupDirectory != null) {
      return;
    }
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final String rootPath =
        '${appDocDir.path}${Platform.pathSeparator}FLPaint${Platform.pathSeparator}backup';
    final Directory manual = Directory(
      '$rootPath${Platform.pathSeparator}manual',
    );
    final Directory autosave = Directory(
      '$rootPath${Platform.pathSeparator}autosave',
    );
    await Future.wait<void>([
      manual.create(recursive: true),
      autosave.create(recursive: true),
    ]);
    _manualBackupDirectory = manual;
    _autosaveBackupDirectory = autosave;
    _backupDirectoriesReady = true;
  }

  void _startAutosaveTimer() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer.periodic(_autosaveInterval, (_) {
      unawaited(_runAutosaveBackupSafely());
    });
  }

  Future<void> _runAutosaveBackupSafely() async {
    try {
      await saveAutosaveBackup();
    } catch (_) {
      // Ignore autosave errors and keep drawing responsive.
    }
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
    const int sourceSize = _toneTileSize * _toneSuperSampleScale;
    final double sourceScale = _toneSuperSampleScale.toDouble();
    final sourceRecorder = ui.PictureRecorder();
    final sourceCanvas = Canvas(sourceRecorder);
    sourceCanvas.drawColor(Colors.transparent, BlendMode.src);
    final dotPaint = Paint()
      ..color = const Color(0xFF000000)
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
      case DrawingLayer.layerC:
        _isLayerCVisible = isVisible;
        break;
    }
    notifyListeners();
  }

  void setLayerOpacity(DrawingLayer layer, double opacity) {
    final clamped = opacity.clamp(0.0, 1.0).toDouble();
    _setLayerOpacityValue(layer, clamped);
    notifyListeners();
  }

  Future<void> mergeLayersToActiveLayer() async {
    final Size canvasSize =
        _canvasSize == Size.zero ? _ioCanvasSize : _canvasSize;
    if (canvasSize == Size.zero) return;

    _saveState();
    final List<ui.Image> snapshots = await Future.wait<ui.Image>(
      _backupLayers.map((DrawingLayer layer) {
        return _renderLayerSnapshot(layer, canvasSize);
      }),
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final Rect bounds =
        Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height);
    canvas.drawColor(Colors.transparent, BlendMode.src);

    for (int i = 0; i < _backupLayers.length; i++) {
      final double opacity = _layerOpacityFor(_backupLayers[i]);
      if (opacity <= 0) continue;
      canvas.saveLayer(
        bounds,
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
      canvas.drawImage(snapshots[i], Offset.zero, Paint());
      canvas.restore();
    }

    final picture = recorder.endRecording();
    final ui.Image merged = await picture.toImage(
      canvasSize.width.ceil(),
      canvasSize.height.ceil(),
    );

    for (final DrawingLayer layer in _backupLayers) {
      _setLayerBaseImage(layer, null);
      _clearLayerLines(layer);
    }
    _placements.clear();

    _setLayerBaseImage(_activeLayer, merged);
    _setLayerOpacityValue(_activeLayer, 1.0);
    _setLayerVisibilityValue(_activeLayer, true);
    _lassoPoints.clear();
    _isDrawingLasso = false;
    _resetSelectionState();
    notifyListeners();
  }

  Future<void> importImageFromDialog() async {
    Uint8List bytes;
    if (Platform.isAndroid) {
      final String? filePath = await FlutterFileDialog.pickFile(
        params: const OpenFileDialogParams(
          dialogType: OpenFileDialogType.document,
          fileExtensionsFilter: ['png', 'jpg', 'jpeg'],
          mimeTypesFilter: ['image/*'],
          copyFileToCacheDir: true,
        ),
      );
      if (filePath == null) return;
      bytes = await File(filePath).readAsBytes();
    } else {
      final XFile? file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Image',
            extensions: ['png', 'jpg', 'jpeg'],
          ),
        ],
      );
      if (file == null) return;
      bytes = await file.readAsBytes();
    }
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
    if (_isLayerCVisible && _layerCOpacity > 0) {
      _paintLayerCompositeForExport(
        canvas,
        size,
        DrawingLayer.layerC,
        _layerCOpacity,
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
    _paintLayerSourceContents(canvas, layer);
    if (_selection != null && _selection!.layer == layer) {
      if (_selectionMasksSource) {
        _clearSelectionArea(canvas, _selection!);
      }
      _paintSelection(
        canvas,
        _selection!,
      );
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

  Future<void> createManualBackup() async {
    await _ensureBackupDirectories();
    await _withBackupLock(() async {
      await _performLayerBackupSet(
        directory: _manualBackupDirectory!,
        baseName: _formatBackupId(DateTime.now()),
        useLatestNames: false,
      );
    });
  }

  Future<void> saveAutosaveBackup() async {
    await _ensureBackupDirectories();
    await _withBackupLock(() async {
      await _performLayerBackupSet(
        directory: _autosaveBackupDirectory!,
        baseName: 'latest',
        useLatestNames: true,
      );
      await _cleanupAutosaveDirectory();
    });
  }

  Future<List<LayerBackupSet>> listAvailableBackups() async {
    await _ensureBackupDirectories();
    final List<LayerBackupSet> backups = [];

    final RegExp manualPattern =
        RegExp(r'^(\d{8}-\d{6})-layer([ABC])\.png$', caseSensitive: false);
    final Map<String, Map<String, String>> groupedManual = {};
    await for (final entity in _manualBackupDirectory!.list()) {
      if (entity is! File) continue;
      final String fileName = _fileName(entity.path);
      final Match? match = manualPattern.firstMatch(fileName);
      if (match == null) continue;
      final String backupId = match.group(1)!;
      final String layerKey = match.group(2)!.toUpperCase();
      groupedManual.putIfAbsent(backupId, () => <String, String>{});
      groupedManual[backupId]![layerKey] = entity.path;
    }

    for (final entry in groupedManual.entries) {
      final paths = entry.value;
      if (!paths.containsKey('A') ||
          !paths.containsKey('B') ||
          !paths.containsKey('C')) {
        continue;
      }
      final DateTime savedAt = _parseBackupId(entry.key) ??
          await _lastModifiedOfPaths(
            <String>[paths['A']!, paths['B']!, paths['C']!],
          );
      backups.add(
        LayerBackupSet(
          id: entry.key,
          isAutosave: false,
          savedAt: savedAt,
          displayLabel: '${_formatBackupDateTime(savedAt)} (manual)',
          layerAPath: paths['A']!,
          layerBPath: paths['B']!,
          layerCPath: paths['C']!,
        ),
      );
    }

    final String autosaveA =
        '${_autosaveBackupDirectory!.path}${Platform.pathSeparator}latest-layerA.png';
    final String autosaveB =
        '${_autosaveBackupDirectory!.path}${Platform.pathSeparator}latest-layerB.png';
    final String autosaveC =
        '${_autosaveBackupDirectory!.path}${Platform.pathSeparator}latest-layerC.png';
    final bool hasAutosave = await Future.wait<bool>(<Future<bool>>[
      File(autosaveA).exists(),
      File(autosaveB).exists(),
      File(autosaveC).exists(),
    ]).then((List<bool> exists) => exists.every((bool value) => value));
    if (hasAutosave) {
      final DateTime savedAt = await _lastModifiedOfPaths(
        <String>[autosaveA, autosaveB, autosaveC],
      );
      backups.add(
        LayerBackupSet(
          id: 'latest',
          isAutosave: true,
          savedAt: savedAt,
          displayLabel: '${_formatBackupDateTime(savedAt)} (autosave)',
          layerAPath: autosaveA,
          layerBPath: autosaveB,
          layerCPath: autosaveC,
        ),
      );
    }

    backups.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return backups;
  }

  Future<void> restoreBackup(LayerBackupSet backupSet) async {
    final List<ui.Image> images =
        await Future.wait<ui.Image>(<Future<ui.Image>>[
      _decodePngFile(backupSet.layerAPath),
      _decodePngFile(backupSet.layerBPath),
      _decodePngFile(backupSet.layerCPath),
    ]);

    _saveState();
    _setLayerBaseImage(DrawingLayer.layerA, images[0]);
    _setLayerBaseImage(DrawingLayer.layerB, images[1]);
    _setLayerBaseImage(DrawingLayer.layerC, images[2]);
    for (final layer in _backupLayers) {
      _clearLayerLines(layer);
    }
    _placements.clear();
    _currentLine = null;
    _lineStartPoint = null;
    _lassoPoints.clear();
    _isDrawingLasso = false;
    _shapeStart = null;
    _shapeEnd = null;
    _resetSelectionState();
    notifyListeners();
  }

  Future<void> _withBackupLock(Future<void> Function() action) async {
    while (_backupBusy) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    _backupBusy = true;
    try {
      await action();
    } finally {
      _backupBusy = false;
    }
  }

  Future<void> _performLayerBackupSet({
    required Directory directory,
    required String baseName,
    required bool useLatestNames,
  }) async {
    final Size backupSize =
        _canvasSize == Size.zero ? _ioCanvasSize : _canvasSize;
    final List<ui.Image> layerImages = await Future.wait<ui.Image>(
      _backupLayers
          .map((DrawingLayer layer) => _renderLayerSnapshot(layer, backupSize)),
    );

    await Future.wait<void>(<Future<void>>[
      for (int i = 0; i < _backupLayers.length; i++)
        _writeImageAsPng(
          layerImages[i],
          '${directory.path}${Platform.pathSeparator}${_backupFileNameForLayer(baseName, _backupLayers[i], useLatestNames: useLatestNames)}',
        ),
    ]);
  }

  Future<void> _cleanupAutosaveDirectory() async {
    if (_autosaveBackupDirectory == null) return;
    final Set<String> keepFileNames = _backupLayers
        .map(
          (layer) =>
              _backupFileNameForLayer('latest', layer, useLatestNames: true),
        )
        .toSet();
    await for (final entity in _autosaveBackupDirectory!.list()) {
      if (entity is! File) continue;
      final String fileName = _fileName(entity.path);
      if (keepFileNames.contains(fileName)) continue;
      await entity.delete();
    }
  }

  Future<ui.Image> _renderLayerSnapshot(DrawingLayer layer, Size size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);

    _paintLayerSourceContents(canvas, layer);
    if (_selection != null && _selection!.layer == layer) {
      if (_selectionMasksSource) {
        _clearSelectionArea(canvas, _selection!);
      }
      _paintSelection(
        canvas,
        _selection!,
      );
    }

    final picture = recorder.endRecording();
    return picture.toImage(size.width.ceil(), size.height.ceil());
  }

  Future<void> _writeImageAsPng(ui.Image image, String outputPath) async {
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Failed to encode backup image as PNG.');
    }
    await File(outputPath).writeAsBytes(data.buffer.asUint8List(), flush: true);
  }

  Future<ui.Image> _decodePngFile(String path) async {
    final Uint8List bytes = await File(path).readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Backup file is empty: $path');
    }
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  String _backupFileNameForLayer(
    String baseName,
    DrawingLayer layer, {
    required bool useLatestNames,
  }) {
    final String suffix = switch (layer) {
      DrawingLayer.layerA => 'A',
      DrawingLayer.layerB => 'B',
      DrawingLayer.layerC => 'C',
    };
    if (useLatestNames) {
      return 'latest-layer$suffix.png';
    }
    return '$baseName-layer$suffix.png';
  }

  String _formatBackupId(DateTime now) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${twoDigits(now.month)}${twoDigits(now.day)}-${twoDigits(now.hour)}${twoDigits(now.minute)}${twoDigits(now.second)}';
  }

  DateTime? _parseBackupId(String id) {
    final Match? match =
        RegExp(r'^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})$').firstMatch(id);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }

  String _formatBackupDateTime(DateTime dateTime) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${dateTime.year}/${twoDigits(dateTime.month)}/${twoDigits(dateTime.day)} ${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}:${twoDigits(dateTime.second)}';
  }

  Future<DateTime> _lastModifiedOfPaths(List<String> paths) async {
    final List<FileStat> stats = await Future.wait<FileStat>(
        paths.map((String path) => File(path).stat()));
    DateTime latest = stats.first.modified;
    for (final stat in stats.skip(1)) {
      if (stat.modified.isAfter(latest)) {
        latest = stat.modified;
      }
    }
    return latest;
  }

  String _fileName(String path) {
    final String normalized = path.replaceAll('\\', '/');
    final int slash = normalized.lastIndexOf('/');
    return slash >= 0 ? normalized.substring(slash + 1) : normalized;
  }

  void clear() {
    _saveState();
    _lines.clear();
    _placements.clear();
    _currentLine = null;
    _lineStartPoint = null;
    _lassoPoints.clear();
    _isDrawingLasso = false;
    _resetSelectionState();
    _layerABaseImage = null;
    _layerBBaseImage = null;
    _layerCBaseImage = null;
    _shapeStart = null;
    _shapeEnd = null;
    notifyListeners();
  }

  ui.Image? _getLayerBaseImage(DrawingLayer layer) {
    switch (layer) {
      case DrawingLayer.layerA:
        return _layerABaseImage;
      case DrawingLayer.layerB:
        return _layerBBaseImage;
      case DrawingLayer.layerC:
        return _layerCBaseImage;
    }
  }

  double _layerOpacityFor(DrawingLayer layer) {
    switch (layer) {
      case DrawingLayer.layerA:
        return _layerAOpacity;
      case DrawingLayer.layerB:
        return _layerBOpacity;
      case DrawingLayer.layerC:
        return _layerCOpacity;
    }
  }

  void _setLayerOpacityValue(DrawingLayer layer, double opacity) {
    switch (layer) {
      case DrawingLayer.layerA:
        _layerAOpacity = opacity;
        break;
      case DrawingLayer.layerB:
        _layerBOpacity = opacity;
        break;
      case DrawingLayer.layerC:
        _layerCOpacity = opacity;
        break;
    }
  }

  void _setLayerVisibilityValue(DrawingLayer layer, bool isVisible) {
    switch (layer) {
      case DrawingLayer.layerA:
        _isLayerAVisible = isVisible;
        break;
      case DrawingLayer.layerB:
        _isLayerBVisible = isVisible;
        break;
      case DrawingLayer.layerC:
        _isLayerCVisible = isVisible;
        break;
    }
  }

  void _setLayerBaseImage(DrawingLayer layer, ui.Image? image) {
    switch (layer) {
      case DrawingLayer.layerA:
        _layerABaseImage = image;
        break;
      case DrawingLayer.layerB:
        _layerBBaseImage = image;
        break;
      case DrawingLayer.layerC:
        _layerCBaseImage = image;
        break;
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
    const taperOutLen = _pressureTaperOutBase; // 14.0を使用
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

  int _takeNextSequence() => _nextSequence++;

  _DrawingSnapshot _createSnapshot() {
    return _DrawingSnapshot(
      lines: List<DrawnLine>.from(_lines.map(_cloneLine)),
      placements: List<LayerPlacement>.from(_placements.map(_clonePlacement)),
      nextSequence: _nextSequence,
      layerABaseImage: _layerABaseImage,
      layerBBaseImage: _layerBBaseImage,
      layerCBaseImage: _layerCBaseImage,
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
    _placements
      ..clear()
      ..addAll(snapshot.placements.map(_clonePlacement));
    _nextSequence = snapshot.nextSequence;
    _layerABaseImage = snapshot.layerABaseImage;
    _layerBBaseImage = snapshot.layerBBaseImage;
    _layerCBaseImage = snapshot.layerCBaseImage;
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
      sequence: src.sequence,
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

  LayerPlacement _clonePlacement(LayerPlacement src) {
    return LayerPlacement(
      rasterImage: src.rasterImage,
      vectorSourceLayer: src.vectorSourceLayer,
      vectorMaskPath: src.vectorMaskPath == null
          ? null
          : (Path()..addPath(src.vectorMaskPath!, Offset.zero)),
      vectorMaxSequence: src.vectorMaxSequence,
      targetLayer: src.targetLayer,
      sequence: src.sequence,
      sourceLayer: src.sourceLayer,
      sourceMaskPath: src.sourceMaskPath == null
          ? null
          : (Path()..addPath(src.sourceMaskPath!, Offset.zero)),
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

  LassoSelection? _cloneSelection(LassoSelection? src) {
    if (src == null) return null;
    final Path clonedPath = Path()..addPath(src.maskPath, Offset.zero);
    return LassoSelection(
      rasterImage: src.rasterImage,
      maxContentSequence: src.maxContentSequence,
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
      sequence: _takeNextSequence(),
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
      sequence: _takeNextSequence(),
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
      sequence: _takeNextSequence(),
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
      sequence: _takeNextSequence(),
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
      sequence: _takeNextSequence(),
      variableWidth: false,
      isEraser: false,
      isFinished: true,
      layer: _activeLayer,
    ));
  }

  int _maxLayerContentSequence(DrawingLayer layer) {
    int maxSeq = 0;
    for (final DrawnLine line in _lines) {
      if (line.layer == layer) {
        maxSeq = math.max(maxSeq, line.sequence);
      }
    }
    for (final LayerPlacement p in _placements) {
      if (p.sourceLayer == layer || p.targetLayer == layer) {
        maxSeq = math.max(maxSeq, p.sequence);
      }
    }
    return maxSeq;
  }

  Path _pathTranslatedBy(Path source, Offset delta) {
    final Path p = Path()..addPath(source, Offset.zero);
    p.transform(Matrix4.translationValues(delta.dx, delta.dy, 0).storage);
    return p;
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

  void finishLasso(Size size) {
    if (!_isDrawingLasso || _lassoPoints.length < 3) {
      _lassoPoints.clear();
      _isDrawingLasso = false;
      notifyListeners();
      return;
    }

    _saveState();
    final path = Path()..addPolygon(List.of(_lassoPoints), true);
    final bounds = _snapRectToCanvasPixels(path.getBounds(), size);
    _lassoPoints.clear();
    _isDrawingLasso = false;

    if (bounds.width < 2 || bounds.height < 2) {
      notifyListeners();
      return;
    }

    final DrawingLayer layer = _activeLayer;
    final int maxSeq = _maxLayerContentSequence(layer);
    _selection = LassoSelection(
      rasterImage: null,
      maxContentSequence: maxSeq,
      maskPath: path,
      layer: layer,
      baseRect: bounds,
    );
    _selectionMasksSource = true;
    _selectionHandlesFilled = false;
    _selectionMergeToActiveLayer = false;
    notifyListeners();
  }

  /// Rasterize vector selection once (e.g. cut → clipboard) while strokes still exist.
  Future<ui.Image> _rasterizeVectorSelectionToImage(
    LassoSelection selection,
    Size canvasSize,
  ) async {
    final DrawingLayer layer = selection.layer;
    final Path path = Path()..addPath(selection.maskPath, Offset.zero);
    final Rect bounds = selection.baseRect;
    final int sampledWidth = math.max(
      1,
      canvasSize.width.ceil(),
    );
    final int sampledHeight = math.max(
      1,
      canvasSize.height.ceil(),
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);
    canvas.save();
    canvas.clipPath(path, doAntiAlias: false);
    // Render in canvas coordinates first, then crop, to preserve tone pixels.
    _paintLayerSourceContents(canvas, layer);
    canvas.restore();
    final picture = recorder.endRecording();

    final ui.Image maskedLayer = await picture.toImage(
      sampledWidth,
      sampledHeight,
    );

    final cropRecorder = ui.PictureRecorder();
    final cropCanvas = Canvas(cropRecorder);
    cropCanvas.drawColor(Colors.transparent, BlendMode.src);
    cropCanvas.drawImageRect(
      maskedLayer,
      bounds,
      Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      Paint()
        ..isAntiAlias = false
        ..filterQuality = FilterQuality.none,
    );
    final cropPicture = cropRecorder.endRecording();
    return cropPicture.toImage(
      math.max(1, bounds.width.ceil()),
      math.max(1, bounds.height.ceil()),
    );
  }

  Future<void> cutSelectionToClipboard() async {
    if (_selection == null || _canvasSize == Size.zero) return;
    _saveState();
    final LassoSelection selection = _selection!;
    if (selection.rasterImage != null) {
      _clipboardImage = selection.rasterImage;
      _clipboardVector = null;
    } else {
      _clipboardImage =
          await _rasterizeVectorSelectionToImage(selection, _canvasSize);
      _clipboardVector = null;
    }

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
      final LassoSelection s = _selection!;
      if (s.rasterImage != null) {
        _clipboardImage = s.rasterImage;
        _clipboardVector = null;
      } else {
        _clipboardImage = null;
        _clipboardVector = _ClipboardVectorSpec(
          maskPathSource: s.maskPath,
          boundsAtCopy: Rect.fromLTWH(
            s.baseRect.left,
            s.baseRect.top,
            s.baseRect.width,
            s.baseRect.height,
          ),
          layer: s.layer,
          maxContentSequence: s.maxContentSequence,
        );
      }
      _selectionMasksSource = false;
      _selectionHandlesFilled = true;
      _selectionMergeToActiveLayer = true;
      notifyListeners();
      return;
    }

    if (_clipboardVector != null) {
      final _ClipboardVectorSpec v = _clipboardVector!;
      final Size canvasSize =
          _canvasSize == Size.zero ? _ioCanvasSize : _canvasSize;
      final Rect newBaseRect = Rect.fromLTWH(
        (canvasSize.width - v.boundsAtCopy.width) / 2,
        (canvasSize.height - v.boundsAtCopy.height) / 2,
        v.boundsAtCopy.width,
        v.boundsAtCopy.height,
      );
      final Offset delta = newBaseRect.topLeft - v.boundsAtCopy.topLeft;
      final Path newMask = _pathTranslatedBy(v.maskPathCanvas, delta);
      _saveState();
      _selection = LassoSelection(
        rasterImage: null,
        maxContentSequence: v.maxContentSequence,
        maskPath: newMask,
        layer: v.layer,
        baseRect: newBaseRect,
      );
      _selectionMasksSource = false;
      _selectionHandlesFilled = true;
      _selectionMergeToActiveLayer = true;
      _tool = ToolType.lasso;
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
      rasterImage: image,
      maxContentSequence: 0,
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
    bool vertical = true,
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
      rasterImage: textImage,
      maxContentSequence: 0,
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
    final int paddingPx = _textSelectionPaddingPixels(fontSize);
    final Future<ui.Image> renderFuture = vertical
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
            maxWidth: math.max(1.0, maxWidth - (paddingPx * 2)),
          );
    final ui.Image renderedText = await renderFuture;
    return _padImageWithTransparentMargin(
      renderedText,
      paddingPx: paddingPx,
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
          textAlign: TextAlign.start,
          softWrap: true,
          style: TextStyle(
            color: Colors.black,
            fontSize: fontSize,
            height: _horizontalTextLineHeight,
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
          height: _horizontalTextLineHeight,
          fontFamily: fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.start,
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

  int _textSelectionPaddingPixels(double fontSize) {
    return math.max(
      16,
      (fontSize * _horizontalTextLineHeight * _textSelectionPaddingLines)
          .ceil(),
    );
  }

  Future<ui.Image> _padImageWithTransparentMargin(
    ui.Image source, {
    required int paddingPx,
  }) async {
    if (paddingPx <= 0) return source;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);
    canvas.drawImage(
      source,
      Offset(paddingPx.toDouble(), paddingPx.toDouble()),
      Paint(),
    );
    final picture = recorder.endRecording();
    return picture.toImage(
      source.width + (paddingPx * 2),
      source.height + (paddingPx * 2),
    );
  }

  Rect _snapRectToCanvasPixels(Rect rect, Size canvasSize) {
    return Rect.fromLTRB(
      rect.left.floorToDouble().clamp(0.0, canvasSize.width),
      rect.top.floorToDouble().clamp(0.0, canvasSize.height),
      rect.right.ceilToDouble().clamp(0.0, canvasSize.width),
      rect.bottom.ceilToDouble().clamp(0.0, canvasSize.height),
    );
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
      final List<double> glyphRenderWidths = <double>[];
      final List<double> glyphRenderHeights = <double>[];
      final List<_VerticalGlyphKind> glyphKinds = <_VerticalGlyphKind>[];
      final List<Offset> glyphOffsets = <Offset>[];
      final List<double> glyphRotations = <double>[];
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
        final double glyphRotation = _verticalGlyphRotation(sourceGlyph);
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
        final bool quarterTurn = _isQuarterTurn(glyphRotation);
        final double renderWidth =
            quarterTurn ? glyphPainter.height : glyphPainter.width;
        final double renderHeight =
            quarterTurn ? glyphPainter.width : glyphPainter.height;
        glyphPainters.add(glyphPainter);
        glyphRenderWidths.add(renderWidth);
        glyphRenderHeights.add(renderHeight);
        glyphKinds.add(glyphKind);
        glyphOffsets.add(glyphOffset);
        glyphRotations.add(glyphRotation);
        maxGlyphWidth = math.max(maxGlyphWidth, renderWidth);
        maxGlyphHeight = math.max(maxGlyphHeight, renderHeight);
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
          glyphRenderWidths: glyphRenderWidths,
          glyphRenderHeights: glyphRenderHeights,
          glyphKinds: glyphKinds,
          glyphOffsets: glyphOffsets,
          glyphRotations: glyphRotations,
          width: columnWidth,
          height: columnHeight,
          topPadding: maxTopOffset,
        ),
      );
    }

    double totalWidth = 0;
    double totalHeight = 0;
    double globalTopPadding = 0;
    double maxContentHeight = 0;
    for (int i = 0; i < columns.length; i++) {
      totalWidth += columns[i].width;
      if (i > 0) {
        totalWidth += columnGap;
      }
      globalTopPadding = math.max(globalTopPadding, columns[i].topPadding);
      maxContentHeight = math.max(
        maxContentHeight,
        columns[i].height - columns[i].topPadding,
      );
    }
    totalHeight = globalTopPadding + maxContentHeight;

    final int width = math.max(1, totalWidth.ceil());
    final int height = math.max(1, totalHeight.ceil());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);
    double rightEdge = totalWidth;
    for (final column in columns) {
      final double x = rightEdge - column.width;
      double y = globalTopPadding;
      final double columnCenterX = x + column.width / 2;
      for (int i = 0; i < column.glyphPainters.length; i++) {
        final TextPainter glyphPainter = column.glyphPainters[i];
        final double glyphWidth = column.glyphRenderWidths[i];
        final double glyphHeight = column.glyphRenderHeights[i];
        final Offset glyphOffset = column.glyphOffsets[i];
        final double glyphRotation = column.glyphRotations[i];
        final double cellTop = y;
        double glyphX = columnCenterX - glyphWidth / 2;
        double glyphY = cellTop + (glyphAdvance - glyphHeight) / 2;
        glyphX += glyphOffset.dx;
        glyphY += glyphOffset.dy;
        canvas.save();
        if (_isQuarterTurn(glyphRotation)) {
          final Offset cellCenter =
              Offset(glyphX + glyphWidth / 2, glyphY + glyphHeight / 2);
          canvas.translate(cellCenter.dx, cellCenter.dy);
          canvas.rotate(glyphRotation);
          canvas.translate(-glyphPainter.width / 2, -glyphPainter.height / 2);
          glyphPainter.paint(canvas, Offset.zero);
        } else {
          glyphPainter.paint(canvas, Offset(glyphX, glyphY));
        }
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

    double rightOffset = fontSize * 0.20;
    double upOffset = fontSize * 0.18;

    if (glyph == '。' || glyph == '．') {
      rightOffset = fontSize * 0.42;
      upOffset = fontSize * 0.44;
    } else if (glyph == '、' || glyph == '，') {
      rightOffset = fontSize * 0.54;
      upOffset = fontSize * 0.43;
    } else if (glyph == '〜' || glyph == '～') {
      rightOffset = 0.0;
      upOffset = 0.0;
    } else if (glyph == '！' || glyph == '？') {
      rightOffset = fontSize * 0.36;
      upOffset = fontSize * 0.22;
    }

    if (glyph == '。' || glyph == '．' || glyph == '、' || glyph == '，') {
      rightOffset += _verticalPunctuationNudgePoints;
      upOffset += _verticalPunctuationNudgePoints;
    }

    return Offset(rightOffset, -upOffset);
  }

  String _normalizeVerticalGlyph(String glyph) {
    if (glyph == 'ー' || glyph == 'ｰ') {
      return '｜';
    }
    return glyph;
  }

  double _verticalGlyphRotation(String glyph) {
    if (glyph == '〜' || glyph == '～') {
      return math.pi / 2;
    }
    return 0.0;
  }

  bool _isQuarterTurn(double radians) {
    return (radians.abs() - (math.pi / 2)).abs() < 0.0001;
  }

  Future<ui.Image> _renderLayerWithClearedSelection(
    Size size,
    DrawingLayer layer,
    LassoSelection selection,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);
    _paintLayerSourceContents(canvas, layer);
    _clearSelectionArea(canvas, selection);
    final picture = recorder.endRecording();
    return picture.toImage(size.width.ceil(), size.height.ceil());
  }

  // Selection manipulation
  Map<SelectionHandle, Offset> _handlePositions(LassoSelection selection) {
    final corners = selection.transformedCorners();
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
    _placements.add(
      LayerPlacement(
        rasterImage: selection.rasterImage,
        vectorSourceLayer:
            selection.rasterImage == null ? selection.layer : null,
        vectorMaskPath: selection.rasterImage == null
            ? (Path()..addPath(selection.maskPath, Offset.zero))
            : null,
        vectorMaxSequence: selection.rasterImage == null
            ? selection.maxContentSequence
            : null,
        targetLayer: layer,
        sequence: _takeNextSequence(),
        sourceLayer: clearSelectionArea ? selection.layer : null,
        sourceMaskPath: clearSelectionArea
            ? (Path()..addPath(selection.maskPath, Offset.zero))
            : null,
        baseRect: Rect.fromLTWH(
          selection.baseRect.left,
          selection.baseRect.top,
          selection.baseRect.width,
          selection.baseRect.height,
        ),
        translation: selection.translation,
        scaleX: selection.scaleX,
        scaleY: selection.scaleY,
        rotation: selection.rotation,
      ),
    );
    _resetSelectionState();
    notifyListeners();
  }

  // Painting helpers shared with CustomPainter and off-screen rendering
  void _paintLayerSourceContents(
    Canvas canvas,
    DrawingLayer layer,
  ) {
    LayerCompositePainter.paintSourceContentsUpTo(
      canvas,
      layer,
      kLayerCompositeMaxSequence,
      allLines: _lines,
      allPlacements: _placements,
      layerABaseImage: _layerABaseImage,
      layerBBaseImage: _layerBBaseImage,
      layerCBaseImage: _layerCBaseImage,
      tone30Shader: _tone30Shader,
      tone60Shader: _tone60Shader,
      tone80Shader: _tone80Shader,
    );
  }

  void _clearSelectionArea(Canvas canvas, LassoSelection selection) {
    canvas.drawPath(
      selection.maskPath,
      Paint()
        ..blendMode = BlendMode.clear
        ..isAntiAlias = false,
    );
  }

  void _paintSelection(
    Canvas canvas,
    LassoSelection selection,
  ) {
    LayerCompositePainter.paintLassoSelection(
      canvas,
      selection,
      allLines: _lines,
      allPlacements: _placements,
      layerABaseImage: _layerABaseImage,
      layerBBaseImage: _layerBBaseImage,
      layerCBaseImage: _layerCBaseImage,
      tone30Shader: _tone30Shader,
      tone60Shader: _tone60Shader,
      tone80Shader: _tone80Shader,
    );
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

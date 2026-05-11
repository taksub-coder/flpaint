import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/models/drawing.dart';
import 'package:myapp/painting/layer_composite_painter.dart';
import 'package:myapp/providers/drawing_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('raster lasso selection painting honors scale transform', () async {
    final ui.Image source = await _solidImage(
      const Size(2, 2),
      const Color(0xFFFF0000),
    );
    final LassoSelection selection = LassoSelection(
      rasterImage: source,
      rasterSampling: RasterSamplingMode.pixelated,
      maskPath: Path()..addRect(const Rect.fromLTWH(10, 10, 2, 2)),
      layer: DrawingLayer.layerA,
      baseRect: const Rect.fromLTWH(10, 10, 2, 2),
      scaleX: 3,
      scaleY: 2,
    );

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);
    LayerCompositePainter.paintLassoSelection(
      canvas,
      selection,
      canvasSize: const Size(40, 40),
      allLines: const <DrawnLine>[],
      allPlacements: const <LayerPlacement>[],
      layerABaseImage: null,
      layerBBaseImage: null,
      layerCBaseImage: null,
      layerABaseSampling: RasterSamplingMode.pixelated,
      layerBBaseSampling: RasterSamplingMode.pixelated,
      layerCBaseSampling: RasterSamplingMode.pixelated,
      tone30Shader: null,
      tone60Shader: null,
      tone80Shader: null,
    );
    final ui.Image rendered = await recorder.endRecording().toImage(40, 40);

    expect(await _pixelColor(rendered, 13, 11), const Color(0xFFFF0000));

    source.dispose();
    rendered.dispose();
  });

  test('selection and committed placement preserve scale through undo redo',
      () async {
    final DrawingProvider provider = DrawingProvider();
    provider.setCanvasSize(const Size(100, 100), pixelRatio: 1);

    await provider.addTextToActiveLayer(
      text: 'A',
      context: null,
      vertical: false,
    );
    provider.setSelectionTransform(scaleX: 2, scaleY: 1.5);
    expect(provider.selection!.scaleX, 2);
    expect(provider.selection!.scaleY, 1.5);

    await provider.commitSelection();
    expect(provider.placements.single.scaleX, 2);
    expect(provider.placements.single.scaleY, 1.5);

    provider.undo();
    expect(provider.selection, isNotNull);
    expect(provider.selection!.scaleX, 2);
    expect(provider.selection!.scaleY, 1.5);

    provider.redo();
    expect(provider.placements.single.scaleX, 2);
    expect(provider.placements.single.scaleY, 1.5);
  });

  test('selection handle hit target supports touch resize', () {
    final DrawingProvider provider = DrawingProvider()
      ..setCanvasSize(const Size(100, 100), pixelRatio: 1)
      ..setTool(ToolType.lasso);

    provider.startLasso(const Offset(20, 20));
    provider.extendLasso(const Offset(80, 20));
    provider.extendLasso(const Offset(80, 80));
    provider.extendLasso(const Offset(20, 80));
    provider.finishLasso(const Size(100, 100));

    final Offset bottomRight =
        provider.getSelectionHandles()[SelectionHandle.cornerBR]!;

    expect(
      provider.hitTestSelection(bottomRight + const Offset(20, 0)),
      SelectionHandle.cornerBR,
    );
  });
}

Future<ui.Image> _solidImage(Size size, Color color) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = color,
  );
  return recorder.endRecording().toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
}

Future<Color> _pixelColor(ui.Image image, int x, int y) async {
  final ByteData? data = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  if (data == null) {
    throw StateError('Failed to read image bytes.');
  }
  final Uint8List bytes = data.buffer.asUint8List();
  final int index = ((y * image.width) + x) * 4;
  return Color.fromARGB(
    bytes[index + 3],
    bytes[index],
    bytes[index + 1],
    bytes[index + 2],
  );
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/models/drawing.dart';
import 'package:myapp/painting/layer_composite_painter.dart';
import 'package:myapp/providers/drawing_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('scaled raster edges stay nearest-neighbor without mixed pixels',
      () async {
    final ui.Image source = await _verticalStripeImage();
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    LayerCompositePainter.paintSourceContentsUpTo(
      canvas,
      DrawingLayer.layerA,
      kLayerCompositeMaxSequence,
      canvasSize: const Size(4, 2),
      allLines: const <DrawnLine>[],
      allPlacements: const <LayerPlacement>[],
      layerABaseImage: source,
      layerBBaseImage: null,
      layerCBaseImage: null,
      layerABaseSampling: RasterSamplingMode.pixelated,
      layerBBaseSampling: RasterSamplingMode.pixelated,
      layerCBaseSampling: RasterSamplingMode.pixelated,
      tone30Shader: null,
      tone60Shader: null,
      tone80Shader: null,
    );

    final ui.Image rendered = await recorder.endRecording().toImage(4, 2);
    final List<Color> pixels = await _readPixels(rendered);

    for (final Color pixel in pixels) {
      final bool isPureRed =
          pixel.red == 255 && pixel.green == 0 && pixel.blue == 0;
      final bool isPureBlue =
          pixel.red == 0 && pixel.green == 0 && pixel.blue == 255;
      expect(
        isPureRed || isPureBlue,
        isTrue,
        reason:
            'Unexpected blended pixel: r=${pixel.red}, g=${pixel.green}, b=${pixel.blue}',
      );
    }
  });

  test('provider stores pointer geometry as integer pixels', () {
    final DrawingProvider provider = DrawingProvider();

    provider.startNewLine(const Offset(1.4, 2.6));
    provider.addPoint(
      const Offset(8.49, 2.51),
      const Offset(1.4, 2.6),
      preserveExactPoint: true,
    );

    final DrawnLine line = provider.lines.single;
    expect(line.points[0].offset, const Offset(1, 3));
    expect(line.points[1].offset, const Offset(8, 3));
  });
}

Future<ui.Image> _verticalStripeImage() async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 1, 2),
    Paint()
      ..color = const Color(0xFFFF0000)
      ..isAntiAlias = false,
  );
  canvas.drawRect(
    const Rect.fromLTWH(1, 0, 1, 2),
    Paint()
      ..color = const Color(0xFF0000FF)
      ..isAntiAlias = false,
  );
  return recorder.endRecording().toImage(2, 2);
}

Future<List<Color>> _readPixels(ui.Image image) async {
  final ByteData? data = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  if (data == null) {
    throw StateError('Failed to read rendered pixels.');
  }
  final Uint8List bytes = data.buffer.asUint8List();
  final List<Color> pixels = <Color>[];
  for (int i = 0; i < bytes.length; i += 4) {
    pixels.add(Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]));
  }
  return pixels;
}

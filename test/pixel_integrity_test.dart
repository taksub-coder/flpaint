import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

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
      final bool isPureRed = _colorByte(pixel.r) == 255 &&
          _colorByte(pixel.g) == 0 &&
          _colorByte(pixel.b) == 0;
      final bool isPureBlue = _colorByte(pixel.r) == 0 &&
          _colorByte(pixel.g) == 0 &&
          _colorByte(pixel.b) == 255;
      expect(
        isPureRed || isPureBlue,
        isTrue,
        reason: 'Unexpected blended pixel: r=${_colorByte(pixel.r)}, '
            'g=${_colorByte(pixel.g)}, b=${_colorByte(pixel.b)}',
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

  test('pen strokes render with anti-aliased smooth edges', () async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    LayerCompositePainter.paintSourceContentsUpTo(
      canvas,
      DrawingLayer.layerA,
      kLayerCompositeMaxSequence,
      canvasSize: const Size(40, 24),
      allLines: <DrawnLine>[
        DrawnLine(
          <Point>[
            Point(const Offset(3, 18), 5),
            Point(const Offset(11, 3), 5),
            Point(const Offset(20, 17), 5),
            Point(const Offset(31, 5), 5),
          ],
          color: Colors.black,
          width: 5,
          tool: ToolType.pen,
          variableWidth: false,
          isFinished: true,
          layer: DrawingLayer.layerA,
        ),
      ],
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

    final ui.Image rendered = await recorder.endRecording().toImage(40, 24);
    final List<Color> pixels = await _readPixels(rendered);

    expect(
      pixels.any((Color pixel) {
        final int alpha = _colorByte(pixel.a);
        return alpha > 0 && alpha < 255;
      }),
      isTrue,
      reason: 'Pen strokes must keep smooth anti-aliased edge pixels.',
    );
  });

  test('pressure stroke widths ease in without abrupt integer steps', () {
    final DrawingProvider provider = DrawingProvider()
      ..setTool(ToolType.pressure)
      ..setPenStrokeWidth(20);

    provider.startNewLine(Offset.zero);
    Offset previous = Offset.zero;
    for (int x = 4; x <= 80; x += 4) {
      final point = Offset(x.toDouble(), 0);
      provider.addPoint(point, previous, preserveExactPoint: true);
      previous = point;
    }

    final List<double> widths =
        provider.lines.single.points.map((point) => point.width).toList();
    final List<double> jumps = <double>[
      for (int i = 1; i < widths.length; i++) (widths[i] - widths[i - 1]).abs(),
    ];

    expect(widths.any((width) => width != width.roundToDouble()), isTrue);
    expect(jumps.reduce(math.max), lessThan(7.0));
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
    pixels.add(
        Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]));
  }
  return pixels;
}

int _colorByte(double channel) {
  return (channel * 255.0).round().clamp(0, 255);
}

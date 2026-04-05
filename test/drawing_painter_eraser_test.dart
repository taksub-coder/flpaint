import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/models/drawing.dart';
import 'package:myapp/widgets/drawing_canvas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('eraser only clears the active layer contents', () async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    final DrawingPainter painter = DrawingPainter(
      allLines: <DrawnLine>[
        DrawnLine(
          <Point>[
            Point(const Offset(2, 12), 8),
            Point(const Offset(22, 12), 8),
          ],
          color: Colors.black,
          width: 8,
          tool: ToolType.pen,
          sequence: 1,
          variableWidth: false,
          isFinished: true,
          layer: DrawingLayer.layerA,
        ),
        DrawnLine(
          <Point>[
            Point(const Offset(2, 12), 8),
            Point(const Offset(22, 12), 8),
          ],
          color: Colors.black,
          width: 8,
          tool: ToolType.pen,
          sequence: 2,
          variableWidth: false,
          isFinished: true,
          layer: DrawingLayer.layerB,
        ),
        DrawnLine(
          <Point>[
            Point(const Offset(2, 12), 8),
            Point(const Offset(22, 12), 8),
          ],
          color: Colors.black,
          width: 8,
          tool: ToolType.eraser,
          sequence: 3,
          variableWidth: false,
          isEraser: true,
          eraserAlpha: 1.0,
          isFinished: true,
          layer: DrawingLayer.layerB,
        ),
      ],
      isLayerAVisible: true,
      isLayerBVisible: true,
      isLayerCVisible: true,
      layerAOpacity: 1.0,
      layerBOpacity: 1.0,
      layerCOpacity: 1.0,
      layerABaseImage: null,
      layerBBaseImage: null,
      layerCBaseImage: null,
      layerABaseSampling: RasterSamplingMode.pixelated,
      layerBBaseSampling: RasterSamplingMode.pixelated,
      layerCBaseSampling: RasterSamplingMode.pixelated,
      tone30Shader: null,
      tone60Shader: null,
      tone80Shader: null,
      placements: const <LayerPlacement>[],
      selection: null,
      selectionMasksSource: true,
      selectionHandlesFilled: false,
      lassoDraft: const <Offset>[],
      isDrawingLasso: false,
      handles: const <SelectionHandle, Offset>{},
      currentTool: ToolType.pen,
      currentStrokeWidth: 5,
      shapeStart: null,
      shapeEnd: null,
      linesStartPointRatioA: 0.12,
      linesStartPointRatioB: 0.24,
      radialPreviewCenter: null,
      radialPreviewStartAngle: null,
      radialPreviewSweepAngle: 0.0,
      radialPreviewLineCount: 0,
      radialPreviewRadius: 0.0,
      canvasRevision: 1,
      layerContentRevision: 1,
      canvasSize: const Size(24, 24),
      canvasVisualOffset: Offset.zero,
    );

    painter.paint(canvas, const Size(24, 24));
    final ui.Image image = await recorder.endRecording().toImage(24, 24);
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);

    expect(data, isNotNull);
    final Uint8List bytes = data!.buffer.asUint8List();
    const int pixelIndex = ((12 * 24) + 12) * 4;
    final Color center = Color.fromARGB(
      bytes[pixelIndex + 3],
      bytes[pixelIndex],
      bytes[pixelIndex + 1],
      bytes[pixelIndex + 2],
    );

    expect((center.a * 255.0).round(), greaterThan(0));
    expect((center.r * 255.0).round(), 0);
    expect((center.g * 255.0).round(), 0);
    expect((center.b * 255.0).round(), 0);
  });
}

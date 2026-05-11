import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:myapp/models/drawing.dart';
import 'package:myapp/painting/layer_composite_painter.dart';
import 'package:myapp/providers/drawing_provider.dart';
import 'package:myapp/widgets/drawing_canvas.dart';

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
    expect(_alphaByte(await _pixelColor(rendered, 15, 11)), 0);

    source.dispose();
    rendered.dispose();
  });

  test('committed raster placement painting honors scale transform', () async {
    final ui.Image source = await _solidImage(
      const Size(2, 2),
      const Color(0xFFFF0000),
    );
    final LayerPlacement placement = LayerPlacement(
      rasterImage: source,
      rasterSampling: RasterSamplingMode.pixelated,
      targetLayer: DrawingLayer.layerA,
      baseRect: const Rect.fromLTWH(10, 10, 2, 2),
      scaleX: 3,
      scaleY: 2,
    );

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);
    LayerCompositePainter.paintPlacement(
      canvas,
      placement,
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
    expect(_alphaByte(await _pixelColor(rendered, 15, 11)), 0);

    source.dispose();
    rendered.dispose();
  });

  test('vector lasso selection painting honors scale transform', () async {
    final DrawnLine line = DrawnLine(
      const <Point>[],
      color: const Color(0xFFFF0000),
      width: 1,
      tool: ToolType.fillRect,
      sequence: 1,
      variableWidth: false,
      shapeRect: const Rect.fromLTWH(10, 10, 2, 2),
    );
    final LassoSelection selection = LassoSelection(
      maskPath: Path()..addRect(const Rect.fromLTWH(10, 10, 2, 2)),
      layer: DrawingLayer.layerA,
      baseRect: const Rect.fromLTWH(10, 10, 2, 2),
      maxContentSequence: 1,
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
      allLines: <DrawnLine>[line],
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
    expect(_alphaByte(await _pixelColor(rendered, 15, 11)), 0);

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

  testWidgets('touch dragging lasso corner handle resizes selection',
      (WidgetTester tester) async {
    final DrawingProvider provider = DrawingProvider()
      ..setCanvasSize(const Size(200, 200), pixelRatio: 1)
      ..setTool(ToolType.lasso);

    provider.startLasso(const Offset(40, 40));
    provider.extendLasso(const Offset(100, 40));
    provider.extendLasso(const Offset(100, 100));
    provider.extendLasso(const Offset(40, 100));
    provider.finishLasso(const Size(200, 200));

    await _pumpCanvas(tester, provider);
    await _dragHandle(
      tester,
      provider,
      SelectionHandle.cornerBR,
      const Offset(40, 40),
    );

    expect(provider.selection!.scaleX, greaterThan(1.0));
    expect(provider.selection!.scaleY, greaterThan(1.0));
  });

  testWidgets('small lasso selection resizes without a dead zone',
      (WidgetTester tester) async {
    final DrawingProvider provider = DrawingProvider()
      ..setCanvasSize(const Size(200, 200), pixelRatio: 1)
      ..setTool(ToolType.lasso);

    provider.startLasso(const Offset(40, 40));
    provider.extendLasso(const Offset(60, 40));
    provider.extendLasso(const Offset(60, 60));
    provider.extendLasso(const Offset(40, 60));
    provider.finishLasso(const Size(200, 200));

    await _pumpCanvas(tester, provider);
    await _dragHandle(
      tester,
      provider,
      SelectionHandle.cornerBR,
      const Offset(10, 10),
    );

    expect(provider.selection!.scaleX, greaterThan(1.0));
    expect(provider.selection!.scaleY, greaterThan(1.0));
  });

  testWidgets('touch dragging text corner handle resizes selection',
      (WidgetTester tester) async {
    final DrawingProvider provider = DrawingProvider()
      ..setCanvasSize(const Size(200, 200), pixelRatio: 1)
      ..setTool(ToolType.lasso);

    await provider.addTextToActiveLayer(
      text: 'A',
      context: null,
      vertical: false,
    );

    await _pumpCanvas(tester, provider);
    await _dragHandle(
      tester,
      provider,
      SelectionHandle.cornerBR,
      const Offset(40, 40),
    );

    expect(provider.selection!.scaleX, greaterThan(1.0));
    expect(provider.selection!.scaleY, greaterThan(1.0));
  });

  testWidgets('small text selection resizes without a dead zone',
      (WidgetTester tester) async {
    final DrawingProvider provider = DrawingProvider()
      ..setCanvasSize(const Size(200, 200), pixelRatio: 1)
      ..setTool(ToolType.lasso);

    await provider.addTextToActiveLayer(
      text: 'A',
      context: null,
      fontSize: 8,
      vertical: false,
    );

    await _pumpCanvas(tester, provider);
    await _dragHandle(
      tester,
      provider,
      SelectionHandle.cornerBR,
      const Offset(10, 10),
    );

    expect(provider.selection!.scaleX, greaterThan(1.0));
    expect(provider.selection!.scaleY, greaterThan(1.0));
  });

  testWidgets('touch dragging corner handle resizes inside InteractiveViewer',
      (WidgetTester tester) async {
    final DrawingProvider provider = DrawingProvider()
      ..setCanvasSize(const Size(200, 200), pixelRatio: 1)
      ..setTool(ToolType.lasso);

    provider.startLasso(const Offset(40, 40));
    provider.extendLasso(const Offset(100, 40));
    provider.extendLasso(const Offset(100, 100));
    provider.extendLasso(const Offset(40, 100));
    provider.finishLasso(const Size(200, 200));

    final TransformationController controller = TransformationController(
      Matrix4.identity()..translateByDouble(-500.0, -500.0, 0.0, 1.0),
    );
    bool selectionDragActive = false;
    final GlobalKey viewerKey = GlobalKey();

    Offset toCanvas(Offset globalPoint) {
      final BuildContext context = viewerKey.currentContext!;
      final RenderBox box = context.findRenderObject()! as RenderBox;
      final Offset localPoint = box.globalToLocal(globalPoint);
      return controller.toScene(localPoint) - const Offset(500, 500);
    }

    await tester.pumpWidget(
      ChangeNotifierProvider<DrawingProvider>.value(
        value: provider,
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 200,
                  height: 200,
                  child: InteractiveViewer(
                    key: viewerKey,
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(2000),
                    panEnabled: !selectionDragActive,
                    scaleEnabled: !selectionDragActive,
                    transformationController: controller,
                    child: SizedBox(
                      width: 1200,
                      height: 1200,
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: DrawingCanvas(
                              toCanvas: toCanvas,
                              onSelectionHandleInteractionChanged:
                                  (bool active) {
                                setState(() {
                                  selectionDragActive = active;
                                });
                              },
                              logicalCanvasSize: const Size(200, 200),
                              canvasVisualOffset: const Offset(500, 500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    await _dragInteractiveHandle(
      tester,
      provider,
      SelectionHandle.cornerBR,
      const Offset(40, 40),
    );

    expect(provider.selection!.scaleX, greaterThan(1.0));
    expect(provider.selection!.scaleY, greaterThan(1.0));
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

int _alphaByte(Color color) => (color.a * 255.0).round().clamp(0, 255);

Future<void> _pumpCanvas(
  WidgetTester tester,
  DrawingProvider provider,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<DrawingProvider>.value(
      value: provider,
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: DrawingCanvas(
              logicalCanvasSize: Size(200, 200),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _dragHandle(
  WidgetTester tester,
  DrawingProvider provider,
  SelectionHandle handle,
  Offset delta,
) async {
  final Finder canvas = find.byType(DrawingCanvas);
  final Offset canvasTopLeft = tester.getTopLeft(canvas);
  final Offset handlePosition = provider.getSelectionHandles()[handle]!;
  final TestGesture touch = await tester.createGesture(
    pointer: 101,
    kind: ui.PointerDeviceKind.touch,
  );
  await touch.down(canvasTopLeft + handlePosition);
  await tester.pump();
  await touch.moveTo(canvasTopLeft + handlePosition + delta);
  await tester.pump();
  await touch.up();
  await tester.pump();
}

Future<void> _dragInteractiveHandle(
  WidgetTester tester,
  DrawingProvider provider,
  SelectionHandle handle,
  Offset delta,
) async {
  final Finder viewer = find.byType(InteractiveViewer);
  final Offset viewerTopLeft = tester.getTopLeft(viewer);
  final Offset handlePosition = provider.getSelectionHandles()[handle]!;
  final TestGesture touch = await tester.createGesture(
    pointer: 102,
    kind: ui.PointerDeviceKind.touch,
  );
  await touch.down(viewerTopLeft + handlePosition);
  await tester.pump();
  await touch.moveTo(viewerTopLeft + handlePosition + delta);
  await tester.pump();
  await touch.up();
  await tester.pump();
}

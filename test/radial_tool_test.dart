import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:myapp/models/drawing.dart';
import 'package:myapp/providers/drawing_provider.dart';
import 'package:myapp/widgets/drawing_canvas.dart';
import 'package:myapp/widgets/drawing_controls.dart';
import 'package:myapp/widgets/radial_tool_popup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('radial tool swaps in dedicated controls',
      (WidgetTester tester) async {
    final DrawingProvider drawing = DrawingProvider()..setTool(ToolType.radial);

    await tester.pumpWidget(
      ChangeNotifierProvider<DrawingProvider>.value(
        value: drawing,
        child: const MaterialApp(
          home: Scaffold(
            body: DrawingControls(),
          ),
        ),
      ),
    );

    expect(find.byType(Slider), findsNWidgets(2));
    expect(find.text('P'), findsNothing);
    expect(find.text('E'), findsNothing);
  });

  testWidgets(
      'radial preview commits alternating A and B lines without overlap',
      (WidgetTester tester) async {
    final DrawingProvider drawing = DrawingProvider()
      ..setTool(ToolType.radial)
      ..setActiveLayer(DrawingLayer.layerB)
      ..setPenStrokeWidth(9)
      ..setLinesStartPointRatioA(0.80)
      ..setLinesStartPointRatioB(0.60)
      ..setRadialLineCountA(6)
      ..setRadialLineCountB(6);

    await tester.pumpWidget(
      ChangeNotifierProvider<DrawingProvider>.value(
        value: drawing,
        child: const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                SizedBox(
                  width: 240,
                  height: 240,
                  child: DrawingCanvas(
                    logicalCanvasSize: Size(240, 240),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: RadialToolPopup(),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final Finder canvas = find.byType(DrawingCanvas);
    final Offset centerGlobal = tester.getCenter(canvas);
    final Offset canvasTopLeft = tester.getTopLeft(canvas);
    final Offset centerLocal = centerGlobal - canvasTopLeft;

    drawing.startRadialPreview(centerLocal);
    drawing.updateRadialPreview(centerLocal + const Offset(40, 0));
    drawing.updateRadialPreview(centerLocal + const Offset(0, 40));
    drawing.setRadialPreviewRadius(80);
    await tester.pump();

    expect(drawing.lines, isEmpty);
    expect(drawing.hasRadialPreview, isTrue);
    expect(find.byType(FilledButton), findsOneWidget);

    drawing.commitRadialPreview();
    await tester.pump();

    expect(drawing.hasRadialPreview, isFalse);
    expect(drawing.lines.length, greaterThan(10));
    expect(drawing.lines.every((line) => line.tool == ToolType.radial), isTrue);
    expect(drawing.lines.every((line) => line.layer == DrawingLayer.layerB),
        isTrue);
    expect(drawing.lines.every((line) => line.width == 9), isTrue);
    expect(drawing.lines.every((line) => line.points.length == 2), isTrue);

    final List<double> startRadii = drawing.lines
        .map((line) => (line.points.first.offset - centerLocal).distance)
        .toList(growable: false);
    final List<double> angles = drawing.lines
        .map((line) =>
            (line.points.last.offset - line.points.first.offset).direction)
        .toList(growable: false);

    expect(
      startRadii.where((radius) => (radius - 16.0).abs() <= 1.0).length,
      greaterThan(0),
    );
    expect(
      startRadii.where((radius) => (radius - 32.0).abs() <= 1.0).length,
      greaterThan(0),
    );
    expect(
      angles.toSet().length,
      greaterThan(10),
    );
  });
}

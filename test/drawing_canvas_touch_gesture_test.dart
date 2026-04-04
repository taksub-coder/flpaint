import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:myapp/models/drawing.dart';
import 'package:myapp/providers/drawing_provider.dart';
import 'package:myapp/widgets/drawing_canvas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('single-touch stroke resume does not pan the viewport',
      (WidgetTester tester) async {
    final DrawingProvider drawing = DrawingProvider()..setTool(ToolType.pen);
    final TransformationController controller = TransformationController();

    await tester.pumpWidget(
      ChangeNotifierProvider<DrawingProvider>.value(
        value: drawing,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                height: 240,
                child: InteractiveViewer(
                  transformationController: controller,
                  panEnabled: true,
                  scaleEnabled: true,
                  child: const SizedBox(
                    width: 240,
                    height: 240,
                    child: DrawingCanvas(
                      logicalCanvasSize: Size(240, 240),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final Finder canvas = find.byType(DrawingCanvas);
    final Offset start = tester.getCenter(canvas);

    final TestGesture firstTouch = await tester.createGesture(
      pointer: 1,
      kind: ui.PointerDeviceKind.touch,
    );
    await firstTouch.down(start);
    await tester.pump();
    await firstTouch.moveTo(start + const Offset(24, 0));
    await tester.pump();
    await firstTouch.up();
    await tester.pump(const Duration(milliseconds: 50));

    final TestGesture resumedTouch = await tester.createGesture(
      pointer: 2,
      kind: ui.PointerDeviceKind.touch,
    );
    await resumedTouch.down(start + const Offset(24, 0));
    await tester.pump();
    await resumedTouch.moveTo(start + const Offset(72, 0));
    await tester.pump();
    await resumedTouch.up();
    await tester.pump(const Duration(milliseconds: 800));

    expect(controller.value.getTranslation().x, closeTo(0.0, 0.001));
    expect(controller.value.getTranslation().y, closeTo(0.0, 0.001));
    expect(drawing.lines, hasLength(1));
    expect(drawing.lines.single.points.length, greaterThanOrEqualTo(2));
  });

  testWidgets('two touch points enter canvas pan mode',
      (WidgetTester tester) async {
    final DrawingProvider drawing = DrawingProvider()..setTool(ToolType.pen);
    Offset? lastPanDelta;

    await tester.pumpWidget(
      ChangeNotifierProvider<DrawingProvider>.value(
        value: drawing,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                height: 240,
                child: DrawingCanvas(
                  logicalCanvasSize: const Size(240, 240),
                  onTwoFingerPan: (Offset delta) {
                    lastPanDelta = delta;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final Finder canvas = find.byType(DrawingCanvas);
    final Offset center = tester.getCenter(canvas);
    final Offset firstStart = center + const Offset(-30, 0);
    final Offset secondStart = center + const Offset(30, 0);

    final TestGesture firstTouch = await tester.createGesture(
      pointer: 11,
      kind: ui.PointerDeviceKind.touch,
    );
    final TestGesture secondTouch = await tester.createGesture(
      pointer: 12,
      kind: ui.PointerDeviceKind.touch,
    );

    await firstTouch.down(firstStart);
    await tester.pump();
    await secondTouch.down(secondStart);
    await tester.pump();
    await firstTouch.moveTo(firstStart + const Offset(12, 0));
    await secondTouch.moveTo(secondStart + const Offset(12, 0));
    await tester.pump();
    await firstTouch.up();
    await secondTouch.up();
    await tester.pump();

    expect(lastPanDelta, isNotNull);
    expect(lastPanDelta!.dx, greaterThan(0));
  });
}

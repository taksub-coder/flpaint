import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:myapp/models/drawing.dart';
import 'package:myapp/providers/drawing_provider.dart';
import 'package:myapp/widgets/tool_sidebar.dart';

void main() {
  testWidgets('tool sidebar keeps the requested button order and actions',
      (WidgetTester tester) async {
    final DrawingProvider drawing = DrawingProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<DrawingProvider>.value(
        value: drawing,
        child: const MaterialApp(
          home: Scaffold(
            body: ToolSidebar(),
          ),
        ),
      ),
    );

    final Finder eraser = find.text('E');
    final Finder strokeColor = find.text('Black');
    final Finder divider = find.byType(Divider);
    final Finder line = find.byTooltip('Line');
    final Finder radial = find.byTooltip('Radial lines');
    final Finder rect = find.byTooltip('Rectangle');

    expect(eraser, findsOneWidget);
    expect(strokeColor, findsOneWidget);
    expect(divider, findsOneWidget);
    expect(line, findsOneWidget);
    expect(radial, findsOneWidget);
    expect(rect, findsOneWidget);
    expect(find.text('L'), findsNothing);

    final double eraserY = tester.getTopLeft(eraser).dy;
    final double strokeColorY = tester.getTopLeft(strokeColor).dy;
    final double dividerY = tester.getTopLeft(divider).dy;
    final double lineY = tester.getTopLeft(line).dy;
    final double radialY = tester.getTopLeft(radial).dy;
    final double rectY = tester.getTopLeft(rect).dy;

    expect(strokeColorY, greaterThan(eraserY));
    expect(dividerY, greaterThan(strokeColorY));
    expect(lineY, greaterThan(dividerY));
    expect(radialY, greaterThan(lineY));
    expect(rectY, greaterThan(radialY));

    await tester.tap(radial);
    await tester.pump();
    expect(drawing.currentTool, ToolType.radial);

    await tester.tap(strokeColor);
    await tester.pump();
    expect(drawing.useWhiteStrokeColor, isTrue);
    expect(find.text('White'), findsOneWidget);
  });
}

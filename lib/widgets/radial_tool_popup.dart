import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/drawing_provider.dart';

class RadialToolPopup extends StatelessWidget {
  const RadialToolPopup({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isLinesToolSelected = context.select<DrawingProvider, bool>(
      (drawing) => drawing.isLinesToolSelected,
    );
    if (!isLinesToolSelected) {
      return const SizedBox.shrink();
    }

    final DrawingProvider drawing = context.read<DrawingProvider>();
    final bool hasPreview = context.select<DrawingProvider, bool>(
      (drawing) => drawing.hasRadialPreview,
    );
    final bool canCommit = context.select<DrawingProvider, bool>(
      (drawing) => drawing.canCommitRadialPreview,
    );
    final double strokeWidth = context.select<DrawingProvider, double>(
      (drawing) => drawing.strokeWidth,
    );
    final double diameter = context.select<DrawingProvider, double>(
      (drawing) => drawing.radialPreviewDiameter,
    );
    final double maxDiameter = context.select<DrawingProvider, double>(
      (drawing) => drawing.radialPreviewMaxDiameter,
    );
    final double radialLineDensity = context.select<DrawingProvider, double>(
      (drawing) => drawing.radialLineDensity,
    );
    final String radialLineDensityLabel =
        context.select<DrawingProvider, String>(
      (drawing) => drawing.radialLineDensityLabel,
    );
    final int lineCount = context.select<DrawingProvider, int>(
      (drawing) => drawing.radialPreviewLineCount,
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 220,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          border: Border.all(color: Colors.black, width: 1),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '\u653e\u5c04\u7dda',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hasPreview
                  ? '\u672c\u6570 $lineCount'
                  : '\u4e2d\u5fc3\u70b9\u304b\u3089\u534a\u5f84\u3092\u30c9\u30e9\u30c3\u30b0\u3067\u6307\u5b9a',
              style: TextStyle(
                fontSize: 11,
                color: hasPreview ? Colors.black87 : Colors.black54,
              ),
            ),
            const SizedBox(height: 10),
            _PopupSliderRow(
              label: '\u592a\u3055',
              value: strokeWidth,
              min: 1,
              max: 30,
              divisions: 29,
              valueText: strokeWidth.round().toString(),
              onChanged: drawing.setPenStrokeWidth,
            ),
            const SizedBox(height: 4),
            _PopupSliderRow(
              label: '\u5186\u5f27',
              value: diameter.clamp(0.0, maxDiameter),
              min: 0,
              max: maxDiameter <= 0 ? 1 : maxDiameter,
              divisions: 200,
              valueText: diameter.round().toString(),
              enabled: hasPreview,
              onChanged: (value) => drawing.setRadialPreviewRadius(value / 2.0),
            ),
            const SizedBox(height: 4),
            _PopupSliderRow(
              label: '\u6570',
              value: radialLineDensity,
              min: 0,
              max: 100,
              divisions: 100,
              valueText: radialLineDensityLabel,
              onChanged: drawing.setRadialLineDensity,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canCommit ? drawing.commitRadialPreview : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('\u78ba\u5b9a'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PopupSliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueText;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _PopupSliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueText,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: SizedBox(
        height: 42,
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                label,
                style: const TextStyle(fontSize: 11),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: value.clamp(min, max).toDouble(),
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: enabled ? onChanged : null,
                ),
              ),
            ),
            SizedBox(
              width: 32,
              child: Text(
                valueText,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

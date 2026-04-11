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
    final int radialLineCountA = context.select<DrawingProvider, int>(
      (drawing) => drawing.radialLineCountA,
    );
    final int radialLineCountB = context.select<DrawingProvider, int>(
      (drawing) => drawing.radialLineCountB,
    );
    final int radialTotalLineCount = context.select<DrawingProvider, int>(
      (drawing) => drawing.radialTotalLineCount,
    );
    final double radialOffsetDegreesA = context.select<DrawingProvider, double>(
      (drawing) => drawing.radialOffsetDegreesA,
    );
    final double radialOffsetDegreesB = context.select<DrawingProvider, double>(
      (drawing) => drawing.radialOffsetDegreesB,
    );
    final double radialLengthA = context.select<DrawingProvider, double>(
      (drawing) => drawing.linesStartPointRatioA * 100.0,
    );
    final double radialLengthB = context.select<DrawingProvider, double>(
      (drawing) => drawing.linesStartPointRatioB * 100.0,
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 280,
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
              '放射線',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hasPreview
                  ? '合計 $radialTotalLineCount本 / 1本指で移動 / 2本指で拡大縮小'
                  : 'プレビューを初期化中',
              style: TextStyle(
                fontSize: 11,
                color: hasPreview ? Colors.black87 : Colors.black54,
              ),
            ),
            const SizedBox(height: 10),
            _PopupSliderRow(
              label: '太さ',
              value: strokeWidth,
              min: 1,
              max: 30,
              divisions: 29,
              valueText: strokeWidth.round().toString(),
              onChanged: drawing.setPenStrokeWidth,
            ),
            const SizedBox(height: 4),
            _PopupSliderRow(
              label: '円周',
              value: diameter.clamp(0.0, maxDiameter),
              min: 0,
              max: maxDiameter <= 0 ? 1 : maxDiameter,
              divisions: 250,
              valueText: diameter.round().toString(),
              enabled: hasPreview,
              onChanged: (value) => drawing.setRadialPreviewRadius(value / 2.0),
            ),
            const SizedBox(height: 8),
            const _PopupSectionTitle(
              label: 'A',
              color: Color(0xC0686830),
            ),
            _PopupSliderRow(
              label: '本数',
              value: radialLineCountA.toDouble(),
              min: 4,
              max: 250,
              divisions: 246,
              valueText: radialLineCountA.toString(),
              onChanged: drawing.setRadialLineCountA,
            ),
            _PopupSliderRow(
              label: '角度',
              value: radialOffsetDegreesA,
              min: -180,
              max: 180,
              divisions: 360,
              valueText: radialOffsetDegreesA.round().toString(),
              onChanged: drawing.setRadialOffsetAngleA,
            ),
            _PopupSliderRow(
              label: '長さ',
              value: radialLengthA,
              min: 0,
              max: 100,
              divisions: 100,
              valueText: radialLengthA.round().toString(),
              onChanged: (value) =>
                  drawing.setLinesStartPointRatioA(value / 100.0),
            ),
            const SizedBox(height: 6),
            const _PopupSectionTitle(
              label: 'B',
              color: Color(0xA8287A8B),
            ),
            _PopupSliderRow(
              label: '本数',
              value: radialLineCountB.toDouble(),
              min: 4,
              max: 250,
              divisions: 246,
              valueText: radialLineCountB.toString(),
              onChanged: drawing.setRadialLineCountB,
            ),
            _PopupSliderRow(
              label: '角度',
              value: radialOffsetDegreesB,
              min: -180,
              max: 180,
              divisions: 360,
              valueText: radialOffsetDegreesB.round().toString(),
              onChanged: drawing.setRadialOffsetAngleB,
            ),
            _PopupSliderRow(
              label: '長さ',
              value: radialLengthB,
              min: 0,
              max: 100,
              divisions: 100,
              valueText: radialLengthB.round().toString(),
              onChanged: (value) =>
                  drawing.setLinesStartPointRatioB(value / 100.0),
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
                child: const Text('確定'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PopupSectionTitle extends StatelessWidget {
  final String label;
  final Color color;

  const _PopupSectionTitle({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
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
        height: 40,
        child: Row(
          children: [
            SizedBox(
              width: 34,
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
              width: 38,
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

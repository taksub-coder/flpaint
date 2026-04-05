import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/drawing.dart';
import '../providers/drawing_provider.dart';

class DrawingControls extends StatelessWidget {
  const DrawingControls({super.key});

  @override
  Widget build(BuildContext context) {
    final DrawingProvider drawing = context.read<DrawingProvider>();
    final bool isLinesToolSelected = context.select<DrawingProvider, bool>(
      (drawing) => drawing.isLinesToolSelected,
    );
    final double strokeWidth = context.select<DrawingProvider, double>(
      (drawing) => drawing.strokeWidth,
    );
    final double eraserWidth = context.select<DrawingProvider, double>(
      (drawing) => drawing.eraserWidth,
    );
    final double linesStartPointRatioA =
        context.select<DrawingProvider, double>(
      (drawing) => drawing.linesStartPointRatioA,
    );
    final double linesStartPointRatioB =
        context.select<DrawingProvider, double>(
      (drawing) => drawing.linesStartPointRatioB,
    );
    final DrawingLayer activeLayer =
        context.select<DrawingProvider, DrawingLayer>(
      (drawing) => drawing.activeLayer,
    );
    final bool isLayerAVisible = context.select<DrawingProvider, bool>(
      (drawing) => drawing.isLayerAVisible,
    );
    final bool isLayerBVisible = context.select<DrawingProvider, bool>(
      (drawing) => drawing.isLayerBVisible,
    );
    final bool isLayerCVisible = context.select<DrawingProvider, bool>(
      (drawing) => drawing.isLayerCVisible,
    );
    final double layerAOpacity = context.select<DrawingProvider, double>(
      (drawing) => drawing.layerAOpacity,
    );
    final double layerBOpacity = context.select<DrawingProvider, double>(
      (drawing) => drawing.layerBOpacity,
    );
    final double layerCOpacity = context.select<DrawingProvider, double>(
      (drawing) => drawing.layerCOpacity,
    );

    final double layerASliderValue = (1.0 - layerAOpacity) * 100.0;
    final double layerBSliderValue = (1.0 - layerBOpacity) * 100.0;
    final double layerCSliderValue = (1.0 - layerCOpacity) * 100.0;
    final double radialSliderValueA = linesStartPointRatioA * 100.0;
    final double radialSliderValueB = linesStartPointRatioB * 100.0;
    final Widget layerButtons = SizedBox(
      width: 112,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _LayerRowButtons(
            label: '\u30ec\u30a4\u30e4\u30fcA',
            selected: activeLayer == DrawingLayer.layerA,
            visible: isLayerAVisible,
            onSelect: () => drawing.setActiveLayer(DrawingLayer.layerA),
            onToggleVisible: (value) =>
                drawing.setLayerVisibility(DrawingLayer.layerA, value),
          ),
          const SizedBox(height: 2),
          _LayerRowButtons(
            label: '\u30ec\u30a4\u30e4\u30fcB',
            selected: activeLayer == DrawingLayer.layerB,
            visible: isLayerBVisible,
            onSelect: () => drawing.setActiveLayer(DrawingLayer.layerB),
            onToggleVisible: (value) =>
                drawing.setLayerVisibility(DrawingLayer.layerB, value),
          ),
          const SizedBox(height: 2),
          _LayerRowButtons(
            label: '\u30ec\u30a4\u30e4\u30fcC',
            selected: activeLayer == DrawingLayer.layerC,
            visible: isLayerCVisible,
            onSelect: () => drawing.setActiveLayer(DrawingLayer.layerC),
            onToggleVisible: (value) =>
                drawing.setLayerVisibility(DrawingLayer.layerC, value),
          ),
        ],
      ),
    );

    return SizedBox(
      height: 118,
      child: isLinesToolSelected
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _SliderRow(
                        symbol: 'A\u7dda\u9577',
                        labelWidth: 46,
                        symbolStyle: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6F6A22),
                          height: 1.0,
                        ),
                        value: radialSliderValueA,
                        min: 0,
                        max: 100,
                        divisions: 100,
                        onChanged: (value) =>
                            drawing.setLinesStartPointRatioA(value / 100.0),
                        valueText: radialSliderValueA.round().toString(),
                      ),
                      const SizedBox(height: 2),
                      _SliderRow(
                        symbol: 'B\u7dda\u9577',
                        labelWidth: 46,
                        symbolStyle: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6F6A22),
                          height: 1.0,
                        ),
                        value: radialSliderValueB,
                        min: 0,
                        max: 100,
                        divisions: 100,
                        onChanged: (value) =>
                            drawing.setLinesStartPointRatioB(value / 100.0),
                        valueText: radialSliderValueB.round().toString(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                layerButtons,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _SliderRow(
                        symbol: 'P',
                        value: strokeWidth,
                        min: 1,
                        max: 30,
                        divisions: 29,
                        showTickMarks: true,
                        enableStepFeedback: true,
                        onChanged: drawing.setPenStrokeWidth,
                      ),
                      const SizedBox(height: 2),
                      _SliderRow(
                        symbol: 'E',
                        value: eraserWidth,
                        min: 1,
                        max: 30,
                        divisions: 29,
                        onChanged: drawing.setEraserWidth,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                layerButtons,
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _SliderRow(
                        symbol: 'A',
                        value: layerASliderValue,
                        min: 0,
                        max: 100,
                        divisions: 100,
                        onChanged: (value) => drawing.setLayerOpacity(
                          DrawingLayer.layerA,
                          1.0 - value / 100.0,
                        ),
                        valueText: '${(100.0 - layerASliderValue).round()}',
                      ),
                      const SizedBox(height: 2),
                      _SliderRow(
                        symbol: 'B',
                        value: layerBSliderValue,
                        min: 0,
                        max: 100,
                        divisions: 100,
                        onChanged: (value) => drawing.setLayerOpacity(
                          DrawingLayer.layerB,
                          1.0 - value / 100.0,
                        ),
                        valueText: '${(100.0 - layerBSliderValue).round()}',
                      ),
                      const SizedBox(height: 2),
                      _SliderRow(
                        symbol: 'C',
                        value: layerCSliderValue,
                        min: 0,
                        max: 100,
                        divisions: 100,
                        onChanged: (value) => drawing.setLayerOpacity(
                          DrawingLayer.layerC,
                          1.0 - value / 100.0,
                        ),
                        valueText: '${(100.0 - layerCSliderValue).round()}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SliderRow extends StatefulWidget {
  final String symbol;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final String? valueText;
  final bool showTickMarks;
  final bool enableStepFeedback;
  final double labelWidth;
  final TextStyle? symbolStyle;

  const _SliderRow({
    required this.symbol,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.valueText,
    this.showTickMarks = false,
    this.enableStepFeedback = false,
    this.labelWidth = 14,
    this.symbolStyle,
  });

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  int? _lastFeedbackStep;

  void _handleChanged(double value) {
    final int currentStep = value.round();
    if (widget.enableStepFeedback && _lastFeedbackStep != currentStep) {
      _lastFeedbackStep = currentStep;
      HapticFeedback.selectionClick();
    }
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    _lastFeedbackStep ??= widget.value.round();
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(
            width: widget.labelWidth,
            child: Text(
              widget.symbol,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: widget.symbolStyle ??
                  const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6F6A22),
                    height: 1.0,
                  ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                tickMarkShape: widget.showTickMarks
                    ? const RoundSliderTickMarkShape(tickMarkRadius: 1.5)
                    : SliderTickMarkShape.noTickMark,
                activeTickMarkColor: Colors.black,
                inactiveTickMarkColor: Colors.black26,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: widget.value.clamp(widget.min, widget.max).toDouble(),
                min: widget.min,
                max: widget.max,
                divisions: widget.divisions,
                label: widget.valueText ?? widget.value.toStringAsFixed(0),
                onChanged: _handleChanged,
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(-12, 0),
            child: SizedBox(
              width: 32,
              child: Text(
                widget.valueText ?? widget.value.toStringAsFixed(1),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LayerRowButtons extends StatelessWidget {
  final String label;
  final bool selected;
  final bool visible;
  final VoidCallback onSelect;
  final ValueChanged<bool> onToggleVisible;

  const _LayerRowButtons({
    required this.label,
    required this.selected,
    required this.visible,
    required this.onSelect,
    required this.onToggleVisible,
  });

  @override
  Widget build(BuildContext context) {
    final selectForeground = selected ? Colors.white : Colors.black;
    final selectBackground = selected ? Colors.black : Colors.white;

    return Row(
      children: [
        SizedBox(
          width: 76,
          height: 30,
          child: OutlinedButton(
            onPressed: onSelect,
            style: OutlinedButton.styleFrom(
              backgroundColor: selectBackground,
              foregroundColor: selectForeground,
              side: const BorderSide(color: Colors.black, width: 2),
              padding: const EdgeInsets.symmetric(horizontal: 1),
              shape: const RoundedRectangleBorder(),
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
        const SizedBox(width: 1),
        SizedBox(
          width: 34,
          height: 30,
          child: OutlinedButton(
            onPressed: () => onToggleVisible(!visible),
            style: OutlinedButton.styleFrom(
              backgroundColor: visible ? Colors.black : Colors.white,
              foregroundColor: visible ? Colors.white : Colors.black,
              side: const BorderSide(color: Colors.black, width: 2),
              padding: const EdgeInsets.symmetric(horizontal: 0),
              shape: const RoundedRectangleBorder(),
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              visible ? 'ON' : 'OFF',
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/drawing.dart';
import '../providers/drawing_provider.dart';

class DrawingControls extends StatelessWidget {
  const DrawingControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DrawingProvider>(
      builder: (context, drawing, _) {
        final layerASliderValue = (1.0 - drawing.layerAOpacity) * 100.0;
        final layerBSliderValue = (1.0 - drawing.layerBOpacity) * 100.0;

        return SizedBox(
          height: 82,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SliderRow(
                      symbol: 'P',
                      value: drawing.strokeWidth,
                      min: 1,
                      max: 30,
                      divisions: 29,
                      onChanged: drawing.setPenStrokeWidth,
                    ),
                    const SizedBox(height: 2),
                    _SliderRow(
                      symbol: 'E',
                      value: drawing.eraserWidth,
                      min: 1,
                      max: 30,
                      divisions: 29,
                      onChanged: drawing.setEraserWidth,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 132,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _LayerRowButtons(
                      label: 'レイヤーA',
                      selected: drawing.activeLayer == DrawingLayer.layerA,
                      visible: drawing.isLayerAVisible,
                      onSelect: () => drawing.setActiveLayer(DrawingLayer.layerA),
                      onToggleVisible: (value) =>
                          drawing.setLayerVisibility(DrawingLayer.layerA, value),
                    ),
                    const SizedBox(height: 2),
                    _LayerRowButtons(
                      label: 'レイヤーB',
                      selected: drawing.activeLayer == DrawingLayer.layerB,
                      visible: drawing.isLayerBVisible,
                      onSelect: () => drawing.setActiveLayer(DrawingLayer.layerB),
                      onToggleVisible: (value) =>
                          drawing.setLayerVisibility(DrawingLayer.layerB, value),
                    ),
                  ],
                ),
              ),
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
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String symbol;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final String? valueText;

  const _SliderRow({
    required this.symbol,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.valueText,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(
            width: 14,
            child: Text(
              symbol,
              style: const TextStyle(fontSize: 28, color: Color(0xFF6F6A22), height: 1.0),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: value.clamp(min, max).toDouble(),
                min: min,
                max: max,
                divisions: divisions,
                label: (valueText ?? value.toStringAsFixed(0)),
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              valueText ?? value.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12),
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
        Expanded(
          child: SizedBox(
            height: 30,
            child: OutlinedButton(
              onPressed: onSelect,
              style: OutlinedButton.styleFrom(
                backgroundColor: selectBackground,
                foregroundColor: selectForeground,
                side: const BorderSide(color: Colors.black, width: 2),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                shape: const RoundedRectangleBorder(),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        SizedBox(
          width: 46,
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
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }
}

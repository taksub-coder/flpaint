import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/drawing_provider.dart';

class DrawingControls extends StatelessWidget {
  const DrawingControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DrawingProvider>(
      builder: (context, drawing, _) {
        return Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              const Text('太さ'),
              Expanded(
                child: Slider(
                  value: drawing.strokeWidth,
                  min: 1,
                  max: 40,
                  onChanged: drawing.setStrokeWidth,
                ),
              ),
              Text(drawing.strokeWidth.toStringAsFixed(1)),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/drawing.dart';
import '../providers/drawing_provider.dart';

class ToolSidebar extends StatelessWidget {
  const ToolSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DrawingProvider>(
      builder: (context, drawing, _) {
        final selected = drawing.currentTool;
        return Container(
          width: 80,
          color: Colors.grey.shade200,
          child: Column(
            children: [
              const SizedBox(height: 12),
              _ToolButton(
                label: 'P',
                tooltip: '均一線',
                selected: selected == ToolType.pen,
                onTap: () => drawing.setTool(ToolType.pen),
              ),
              const SizedBox(height: 8),
              _ToolButton(
                label: 'T',
                tooltip: '筆圧線',
                selected: selected == ToolType.pressure,
                onTap: () => drawing.setTool(ToolType.pressure),
              ),
              const SizedBox(height: 8),
              _ToolButton(
                label: 'E',
                tooltip: '消しゴム',
                selected: selected == ToolType.eraser,
                onTap: () => drawing.setTool(ToolType.eraser),
              ),
              const SizedBox(height: 12),
              _ToolButton(
                icon: Icons.gesture,
                tooltip: 'なげなわ',
                selected: selected == ToolType.lasso,
                onTap: () => drawing.setTool(ToolType.lasso),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ToolButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  final String tooltip;

  const _ToolButton({
    this.label,
    this.icon,
    required this.selected,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final child = Center(
      child: icon != null
          ? Icon(icon, size: 18, color: Colors.black87)
          : Text(label ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );

    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? Colors.white : Colors.grey.shade300,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: selected ? Colors.black : Colors.grey.shade500, width: 2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: child,
          ),
        ),
      ),
    );
  }
}

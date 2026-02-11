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
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToolButton(
                  label: 'P',
                  tooltip: 'Pen',
                  selected: selected == ToolType.pen,
                  onTap: () => drawing.setTool(ToolType.pen),
                ),
                const SizedBox(height: 8),
                _ToolButton(
                  label: 'T',
                  tooltip: 'Pressure pen',
                  selected: selected == ToolType.pressure,
                  onTap: () => drawing.setTool(ToolType.pressure),
                ),
                const SizedBox(height: 8),
                _ToolButton(
                  label: 'E',
                  tooltip: 'Eraser',
                  selected: selected == ToolType.eraser,
                  onTap: () => drawing.setTool(ToolType.eraser),
                ),
                const SizedBox(height: 8),
                _ToolButton(
                  label: 'L',
                  tooltip: 'Line',
                  selected: selected == ToolType.line,
                  onTap: () => drawing.setTool(ToolType.line),
                ),
                const Divider(height: 20),
                _ToolButton(
                  label: '□',
                  tooltip: 'Rectangle',
                  selected: selected == ToolType.rect,
                  onTap: () => drawing.setTool(ToolType.rect),
                ),
                const SizedBox(height: 8),
                _ToolButton(
                  label: '■',
                  tooltip: 'Filled rectangle',
                  selected: selected == ToolType.fillRect,
                  onTap: () => drawing.setTool(ToolType.fillRect),
                ),
                const SizedBox(height: 8),
                _ToolButton(
                  label: '○',
                  tooltip: 'Circle',
                  selected: selected == ToolType.circle,
                  onTap: () => drawing.setTool(ToolType.circle),
                ),
                const SizedBox(height: 8),
                _ToolButton(
                  label: '●',
                  tooltip: 'Filled circle',
                  selected: selected == ToolType.fillCircle,
                  onTap: () => drawing.setTool(ToolType.fillCircle),
                ),
                const SizedBox(height: 12),
                _ToolButton(
                  icon: Icons.gesture,
                  tooltip: 'Lasso select',
                  selected: selected == ToolType.lasso,
                  onTap: () => drawing.setTool(ToolType.lasso),
                ),
                const SizedBox(height: 8),
                _ToolButton(
                  label: 'IN',
                  tooltip: 'Import image',
                  selected: false,
                  onTap: () => drawing.importImageFromDialog(),
                ),
                const SizedBox(height: 8),
                _ToolButton(
                  label: 'EXP',
                  tooltip: 'Export image',
                  selected: false,
                  onTap: () => drawing.exportImageFromDialog(),
                ),
              ],
            ),
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
          : Text(
              label ?? '',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
    );

    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? Colors.white : Colors.grey.shade300,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: selected ? Colors.black : Colors.grey.shade500,
            width: 2,
          ),
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

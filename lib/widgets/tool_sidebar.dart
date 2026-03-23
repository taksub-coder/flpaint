import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/drawing.dart';
import '../providers/drawing_provider.dart';

enum _TextFontOption {
  gothic,
  mincho,
}

enum _TextSizeOption {
  small,
  medium,
  large,
}

enum _TextDirectionOption {
  horizontal,
  vertical,
}

class _TextDialogResult {
  final String text;
  final _TextFontOption fontOption;
  final _TextSizeOption sizeOption;
  final _TextDirectionOption directionOption;

  const _TextDialogResult({
    required this.text,
    required this.fontOption,
    required this.sizeOption,
    required this.directionOption,
  });
}

class ToolSidebar extends StatelessWidget {
  const ToolSidebar({super.key});

  @override
  Widget build(BuildContext rootContext) {
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
                  label: 'C',
                  tooltip: 'Cut selection',
                  selected: false,
                  onTap: () => drawing.cutSelectionToClipboard(),
                ),
                const SizedBox(height: 8),
                _ToolButton(
                  label: 'CP',
                  tooltip: 'Copy & paste selection',
                  selected: false,
                  onTap: () => drawing.copyPasteSelection(),
                ),
                const SizedBox(height: 8),
                _ToolButton(
                  label: 'Merge',
                  tooltip: 'Merge all layers into the active layer',
                  selected: false,
                  onTap: () => drawing.mergeLayersToActiveLayer(),
                ),
                const SizedBox(height: 8),
                _ToolButton(
                  label: 'あ',
                  tooltip: 'Text input',
                  selected: false,
                  onTap: () {
                    _showTextInputDialog(
                      context: rootContext,
                      drawing: drawing,
                    );
                  },
                ),
                const SizedBox(height: 8),
                _ToolButton(
                  label: '30',
                  tooltip: 'Tone 30%',
                  selected: selected == ToolType.tone30,
                  onTap: () => drawing.setTool(ToolType.tone30),
                ),
                const SizedBox(height: 8),
                _ToolButton(
                  label: '60',
                  tooltip: 'Tone 60%',
                  selected: selected == ToolType.tone60,
                  onTap: () => drawing.setTool(ToolType.tone60),
                ),
                const SizedBox(height: 8),
                _ToolButton(
                  label: '80',
                  tooltip: 'Tone 80%',
                  selected: selected == ToolType.tone80,
                  onTap: () => drawing.setTool(ToolType.tone80),
                ),
                const SizedBox(height: 8),
                _ToolButton(
                  label: drawing.useWhiteStrokeColor ? 'White' : 'Black',
                  tooltip: 'Toggle stroke color',
                  selected: drawing.useWhiteStrokeColor,
                  onTap: drawing.toggleStrokeColorMode,
                ),
                const SizedBox(height: 8),
                _ToolButton(
                  label: 'Bk',
                  tooltip: 'Backup layers',
                  selected: false,
                  onTap: () => _runManualBackup(
                    context: rootContext,
                    drawing: drawing,
                  ),
                ),
                const SizedBox(height: 8),
                _ToolButton(
                  label: 'Rst',
                  tooltip: 'Restore layers',
                  selected: false,
                  onTap: () => _showRestoreSelector(
                    context: rootContext,
                    drawing: drawing,
                  ),
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
                  onTap: () =>
                      drawing.exportImageFromDialog(context: rootContext),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showTextInputDialog({
    required BuildContext context,
    required DrawingProvider drawing,
  }) async {
    final _TextDialogResult? result = await showDialog<_TextDialogResult>(
      context: context,
      builder: (_) => const _TextInputDialog(),
    );

    if (result == null || result.text.trim().isEmpty) return;
    if (!context.mounted) return;

    final double fontSize = switch (result.sizeOption) {
      _TextSizeOption.small => 21,
      _TextSizeOption.medium => 32,
      _TextSizeOption.large => 64,
    };

    await drawing.addTextToActiveLayer(
      context: context,
      text: result.text,
      fontFamily: result.fontOption == _TextFontOption.mincho ? 'serif' : null,
      fontSize: fontSize,
      vertical: result.directionOption == _TextDirectionOption.vertical,
    );
  }

  Future<void> _runManualBackup({
    required BuildContext context,
    required DrawingProvider drawing,
  }) async {
    try {
      await drawing.createManualBackup();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('バックアップを保存しました。')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('バックアップの保存に失敗しました。')),
      );
    }
  }

  Future<void> _showRestoreSelector({
    required BuildContext context,
    required DrawingProvider drawing,
  }) async {
    try {
      final List<LayerBackupSet> backups = await drawing.listAvailableBackups();
      if (!context.mounted) return;
      if (backups.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('復元できるバックアップがありません。')),
        );
        return;
      }

      final LayerBackupSet? selected = await showDialog<LayerBackupSet>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('保存日時を選択'),
            content: SizedBox(
              width: 360,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: backups.length,
                itemBuilder: (_, index) {
                  final item = backups[index];
                  return ListTile(
                    dense: true,
                    title: Text(item.displayLabel),
                    subtitle: Text(item.isAutosave ? 'autosave' : 'manual'),
                    onTap: () => Navigator.of(dialogContext).pop(item),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('キャンセル'),
              ),
            ],
          );
        },
      );
      if (selected == null || !context.mounted) return;

      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('確認'),
            content: const Text('現在のキャンバスは上書きされます。よろしいですか？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('キャンセル'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('実行'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;

      await drawing.restoreBackup(selected);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('リストアが完了しました。')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('リストアに失敗しました。')),
      );
    }
  }
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog();

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller;
  late final FocusNode _inputFocusNode;
  _TextFontOption _fontOption = _TextFontOption.gothic;
  _TextSizeOption _sizeOption = _TextSizeOption.medium;
  _TextDirectionOption _directionOption = _TextDirectionOption.vertical;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _inputFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestInputFocus();
      // Desktop/IME environments can occasionally miss the first request.
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        _requestInputFocus();
      });
    });
  }

  void _requestInputFocus() {
    if (!mounted) return;
    if (_inputFocusNode.hasFocus) return;
    FocusScope.of(context).requestFocus(_inputFocusNode);
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _apply() {
    Navigator.of(context).pop(
      _TextDialogResult(
        text: _controller.text,
        fontOption: _fontOption,
        sizeOption: _sizeOption,
        directionOption: _directionOption,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('テキスト入力'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _controller,
                focusNode: _inputFocusNode,
                autofocus: true,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                enableInteractiveSelection: true,
                onTap: _requestInputFocus,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '文字を入力',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<_TextFontOption>(
                initialValue: _fontOption,
                decoration: const InputDecoration(
                  labelText: '書体',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: _TextFontOption.gothic,
                    child: Text('ゴシック'),
                  ),
                  DropdownMenuItem(
                    value: _TextFontOption.mincho,
                    child: Text('明朝'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _fontOption = value;
                  });
                  _requestInputFocus();
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<_TextSizeOption>(
                initialValue: _sizeOption,
                decoration: const InputDecoration(
                  labelText: 'サイズ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: _TextSizeOption.small,
                    child: Text('小 (16px)'),
                  ),
                  DropdownMenuItem(
                    value: _TextSizeOption.medium,
                    child: Text('中 (32px)'),
                  ),
                  DropdownMenuItem(
                    value: _TextSizeOption.large,
                    child: Text('大 (64px)'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _sizeOption = value;
                  });
                  _requestInputFocus();
                },
              ),
              const SizedBox(height: 12),
              const Text('方向'),
              const SizedBox(height: 6),
              ToggleButtons(
                constraints: const BoxConstraints(
                  minWidth: 120,
                  minHeight: 38,
                ),
                isSelected: [
                  _directionOption == _TextDirectionOption.horizontal,
                  _directionOption == _TextDirectionOption.vertical,
                ],
                onPressed: (index) {
                  setState(() {
                    _directionOption = index == 0
                        ? _TextDirectionOption.horizontal
                        : _TextDirectionOption.vertical;
                  });
                  _requestInputFocus();
                },
                children: const [
                  Text('横書き'),
                  Text('縦書き'),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: _apply,
          child: const Text('挿入'),
        ),
      ],
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
              style: TextStyle(
                fontSize: (label?.length ?? 0) > 3 ? 11 : 16,
                fontWeight: FontWeight.bold,
              ),
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

import 'package:flutter/material.dart';

import 'lesson_colors.dart';

/// 圆形色板选择行：首位是「未自选色」的占位 [ChoiceChip]（文案如「自动」
/// 「默认」，可带预览色），后接 [lessonPalette]；既有的板外自选色（如外部
/// 导入）插到最前保留展示。课程编辑器与课表编辑器共用。
class ColorSwatchRow extends StatelessWidget {
  /// 当前值：`#RRGGBB`，空串表示未自选。
  final String value;
  final ValueChanged<String> onChanged;

  /// 占位项文案（选中即回传空串）。
  final String emptyLabel;

  /// 占位项的预览色（如课程的自动取色）；null 则不带色点。
  final Color? emptyPreview;

  const ColorSwatchRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.emptyLabel,
    this.emptyPreview,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = parseHexColor(value);
    final swatches = <Color>[...lessonPalette];
    if (current != null &&
        !swatches.any((c) => c.toARGB32() == current.toARGB32())) {
      swatches.insert(0, current);
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          label: Text(emptyLabel),
          avatar: emptyPreview == null
              ? null
              : CircleAvatar(backgroundColor: emptyPreview),
          selected: current == null,
          onSelected: (_) => onChanged(''),
        ),
        for (final c in swatches)
          _RoundSwatch(
            color: c,
            selected: current != null && c.toARGB32() == current.toARGB32(),
            border: Border.all(color: scheme.outlineVariant),
            onTap: () => onChanged(colorToHex(c)),
          ),
      ],
    );
  }
}

class _RoundSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final Border border;
  final VoidCallback onTap;

  const _RoundSwatch({
    required this.color,
    required this.selected,
    required this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: Colors.white, width: 3)
              : border,
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)]
              : null,
        ),
        child: selected
            ? const Icon(Icons.check, size: 20, color: Colors.white)
            : null,
      ),
    );
  }
}

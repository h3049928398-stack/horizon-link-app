import 'package:flutter/material.dart';

import '../l10n.dart';
import 'ios_glass_controls.dart';
import 'liquid_glass.dart';

String _text(BuildContext context, Widget? label) => switch (label) {
  LText(:final data) => context.tr(data),
  Text(:final data) => data ?? '',
  _ => '',
};

double _width(BuildContext context, String text) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: const TextStyle(fontSize: 17)),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: Directionality.of(context),
  )..layout();
  final result = painter.width;
  painter.dispose();
  return result;
}

Widget _toggleTile(
  BuildContext context, {
  Key? key,
  required Widget? title,
  Widget? subtitle,
  Widget? leading,
  required bool value,
  required ValueChanged<bool>? onChanged,
  EdgeInsetsGeometry? padding,
  bool? dense,
  Color? color,
}) {
  return GestureDetector(
    key: key,
    excludeFromSemantics: true,
    onTap: onChanged == null ? null : () => onChanged(!value),
    child: ListTile(
      enabled: onChanged != null,
      title: ExcludeSemantics(child: title),
      subtitle: subtitle == null ? null : ExcludeSemantics(child: subtitle),
      leading: leading == null ? null : ExcludeSemantics(child: leading),
      dense: dense,
      contentPadding: padding,
      trailing: IosOptionControl(
        kind: 'switch',
        labels: const [],
        name: _text(context, title),
        hint: _text(context, subtitle),
        selected: value ? 1 : 0,
        width: 56,
        color: color,
        onSelect: onChanged == null ? null : (i) => onChanged(i == 1),
      ),
    ),
  );
}

extension SystemSwitchTile on SwitchListTile {
  Widget forPhone(BuildContext context) => LiquidGlass.enabledOf(context)
      ? _toggleTile(
          context,
          key: key,
          title: title,
          subtitle: subtitle,
          leading: secondary,
          value: value,
          onChanged: onChanged,
          padding: contentPadding,
          dense: dense,
        )
      : this;
}

extension SystemCheckTile on CheckboxListTile {
  Widget forPhone(BuildContext context) => LiquidGlass.enabledOf(context)
      ? _toggleTile(
          context,
          key: key,
          title: title,
          subtitle: subtitle,
          leading: secondary,
          value: value == true,
          onChanged: onChanged,
          padding: contentPadding,
          dense: dense,
          color: activeColor,
        )
      : this;
}

extension SystemDropdown<T> on DropdownButton<T> {
  Widget forPhone(BuildContext context, String name) {
    if (!LiquidGlass.enabledOf(context)) return this;
    final options = items!;
    final labels = options.map((item) => _text(context, item.child)).toList();
    final selected = options.indexWhere((item) => item.value == value);
    final title = selected < 0 ? '' : labels[selected];
    return IosOptionControl(
      key: key,
      kind: 'menu',
      labels: labels,
      name: name,
      selected: selected,
      width: isExpanded
          ? double.infinity
          : (_width(context, title) + 42).clamp(50, 160),
      onSelect: onChanged == null ? null : (i) => onChanged!(options[i].value),
    );
  }
}

extension SystemSegments<T> on SegmentedButton<T> {
  Widget forPhone(BuildContext context, String name, {bool trailing = false}) {
    if (!LiquidGlass.enabledOf(context)) return this;
    final labels = segments.map((s) => _text(context, s.label)).toList();
    final current = segments.indexWhere((s) => selected.contains(s.value));
    final width =
        labels
            .map((s) => _width(context, s) + 22)
            .reduce((a, b) => a > b ? a : b) *
        labels.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final limit = constraints.maxWidth.clamp(
          0.0,
          MediaQuery.sizeOf(context).width * (trailing ? .45 : .9),
        );
        final menu = width > limit;
        return IosOptionControl(
          key: key,
          kind: menu ? 'menu' : 'segments',
          labels: labels,
          name: name,
          selected: current,
          width: menu && current >= 0
              ? (_width(context, labels[current]) + 42).clamp(0, limit)
              : width.clamp(0, limit),
          onSelect: onSelectionChanged == null
              ? null
              : (i) => onSelectionChanged!({segments[i].value}),
        );
      },
    );
  }
}

extension SystemPopup<T> on PopupMenuButton<T> {
  Widget forPhone(
    BuildContext context, {
    required String symbol,
    int destructive = -1,
    String? name,
  }) {
    if (!LiquidGlass.enabledOf(context)) return this;
    final entries = itemBuilder(context).whereType<PopupMenuItem<T>>().toList();
    return IosOptionControl(
      key: key,
      kind: 'menu',
      symbol: symbol,
      name: name ?? tooltip ?? '',
      selected: initialValue == null
          ? -1
          : entries.indexWhere((e) => e.value == initialValue),
      width: 44,
      destructive: destructive,
      labels: entries.map((e) => _text(context, e.child)).toList(),
      onSelect: !enabled
          ? null
          : (i) => onSelected?.call(entries[i].value as T),
    );
  }
}

Widget phoneChoice(
  BuildContext context, {
  required Widget fallback,
  required String title,
  required bool selected,
  required VoidCallback? onPressed,
  String symbol = '',
  Key? key,
}) {
  if (!LiquidGlass.enabledOf(context)) return fallback;
  return IosOptionControl(
    key: key,
    kind: 'choice',
    labels: [title],
    name: title,
    symbol: symbol,
    selected: selected ? 0 : -1,
    width: symbol.isEmpty ? (_width(context, title) + 22).clamp(44, 200) : 44,
    onSelect: onPressed == null ? null : (_) => onPressed(),
  );
}

extension SystemChoiceChip on ChoiceChip {
  Widget forPhone(BuildContext context) => phoneChoice(
    context,
    fallback: this,
    key: key,
    title: _text(context, label),
    selected: selected,
    onPressed: onSelected == null ? null : () => onSelected!(!selected),
  );
}

extension SystemFilterChip on FilterChip {
  Widget forPhone(BuildContext context) => phoneChoice(
    context,
    fallback: this,
    key: key,
    title: _text(context, label),
    selected: selected,
    onPressed: onSelected == null ? null : () => onSelected!(!selected),
  );
}

extension SystemIconChoice on IconButton {
  Widget forChoice(BuildContext context, bool selected, String symbol) =>
      phoneChoice(
        context,
        fallback: this,
        key: key,
        title: tooltip ?? '',
        symbol: symbol,
        selected: selected,
        onPressed: onPressed,
      );
}

extension SystemTextChoice on ButtonStyleButton {
  Widget forChoice(BuildContext context, bool selected, String title) =>
      phoneChoice(
        context,
        fallback: this,
        key: key,
        title: title,
        selected: selected,
        onPressed: onPressed,
      );
}

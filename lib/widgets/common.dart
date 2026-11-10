import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../theme.dart';

/// Small rounded status label.
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final bool filled;
  const Pill(this.text, {super.key, this.color = Z.muted, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: filled ? Z.ink : color, fontFeatures: Z.tabular)),
    );
  }
}

/// Section heading inside a scrolling page.
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(children: [
        Expanded(child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Z.muted))),
        ?trailing,
      ]),
    );
  }
}

/// Centered message for empty lists.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: Z.line),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Z.muted, height: 1.45)),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ]),
      ),
    );
  }
}

/// Integer stepper: [−] value [+].
class Stepper2 extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int>? onChanged; // null = locked
  final String Function(int)? format;
  const Stepper2({super.key, required this.value, required this.onChanged, this.min = 0, this.max = 99, this.format});

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData i, int d) => IconButton.filledTonal(
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(backgroundColor: Z.raised),
          onPressed: (onChanged == null || value + d < min || value + d > max) ? null : () => onChanged!(value + d),
          icon: Icon(i, size: 18),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      btn(Icons.remove, -1),
      SizedBox(
        width: 44,
        child: Text(format?.call(value) ?? '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, fontFeatures: Z.tabular)),
      ),
      btn(Icons.add, 1),
    ]);
  }
}

/// A labelled settings row.
class SettingRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const SettingRow({super.key, required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: Z.muted, height: 1.35)),
              ),
          ]),
        ),
        const SizedBox(width: 12),
        child,
      ]),
    );
  }
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}

Future<void> copyText(BuildContext context, String text, String what) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, S.t.copied(what));
}

Future<bool> confirm(BuildContext context, String title, String body, {String? ok, bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(body, style: const TextStyle(height: 1.45)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(S.t.cancel)),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Z.danger, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok ?? S.t.ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptText(BuildContext context, String title, {String initial = '', String hint = ''}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(S.t.cancel)),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: Text(S.t.save)),
      ],
    ),
  );
}

/// Small "עב" / "EN" button for the app bar of the main screens.
class LangButton extends StatelessWidget {
  const LangButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: S.t.langTooltip,
      child: TextButton(
        key: const ValueKey('lang-toggle'),
        onPressed: Lang.instance.toggle,
        child: Text(S.t.langButton, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
    );
  }
}

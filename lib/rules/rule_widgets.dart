import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';
import 'rule_section_screen.dart';
import 'rules_data.dart';
import 'smart_search.dart';

/// Bookmarks for rules ("16-5-2") and Q&A ("q:r127", "q:c5574"), persisted.
class RuleBookmarks extends ChangeNotifier {
  RuleBookmarks._();
  static final instance = RuleBookmarks._();
  static const _key = 'zira.rules.bookmarks';

  final Set<String> ids = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    ids.addAll(p.getStringList(_key) ?? const []);
    notifyListeners();
  }

  Future<void> toggle(String id) async {
    ids.contains(id) ? ids.remove(id) : ids.add(id);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, ids.toList());
  }
}

class BookmarkButton extends StatelessWidget {
  final String id;
  const BookmarkButton({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RuleBookmarks.instance,
      builder: (context, _) {
        final on = RuleBookmarks.instance.ids.contains(id);
        return IconButton(
          tooltip: on ? 'הסרת סימנייה' : 'סימנייה',
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          color: on ? Z.gold : Z.line,
          onPressed: () => RuleBookmarks.instance.toggle(id),
          icon: Icon(on ? Icons.bookmark : Icons.bookmark_border),
        );
      },
    );
  }
}

void openRule(BuildContext context, RulesBook book, String id, {String? highlight}) {
  Navigator.push(
      context, MaterialPageRoute(builder: (_) => RuleSectionScreen(book: book, id: id, highlight: highlight)));
}

/// One rule: number badge, English text (left-to-right), tappable links,
/// search highlights, "updated" badge and a bookmark star.
class RuleTile extends StatelessWidget {
  final RulesBook book;
  final Rule rule;
  final String? highlight;
  final bool showBreadcrumb;
  final int indentFrom; // depth that gets no indent
  final VoidCallback? onTap;

  const RuleTile({
    super.key,
    required this.book,
    required this.rule,
    this.highlight,
    this.showBreadcrumb = false,
    this.indentFrom = 1,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = rule;
    final heading = r.isHeading;
    final indent = ((r.depth - indentFrom).clamp(0, 4)) * 14.0;
    final latest = r.changedIn != null && r.changedIn == book.version;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16 + indent, heading ? 14 : 8, 6, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: heading ? Z.blue.withValues(alpha: .16) : Z.raised,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(r.id,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: heading ? Z.blue : Z.muted,
                      fontFeatures: Z.tabular)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (showBreadcrumb)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(_crumb(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: Z.muted)),
                  ),
                RichRuleText(book: book, text: r.text, highlight: highlight, heading: heading),
                if (latest)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: Z.gold.withValues(alpha: .16), borderRadius: BorderRadius.circular(99)),
                      child: Text('Updated in ver ${book.version} · עודכן',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Z.gold)),
                    ),
                  ),
              ]),
            ),
            BookmarkButton(id: r.id),
          ]),
        ),
      ),
    );
  }

  String _crumb() {
    final parts = <String>[book.chapterTitle(rule.chapter)];
    for (final p in book.ancestors(rule.id).where((p) => p.isHeading)) {
      if (p.text != parts.last) parts.add(p.text); // chapter and section often share a name
    }
    return parts.join(' › ');
  }
}

/// Rules / Q&A text with:
///  * "refer to X-Y" → link to that rule,
///  * `<Keyword>` (incl. `<Security A. +1>`) → link to the keyword's section,
///  * search words highlighted (same matching as the search itself).
class RichRuleText extends StatelessWidget {
  final RulesBook book;
  final String text;
  final String? highlight;
  final bool heading;
  final bool bold;
  final bool muted;
  final int? maxLines;

  const RichRuleText({
    super.key,
    required this.book,
    required this.text,
    this.highlight,
    this.heading = false,
    this.bold = false,
    this.muted = false,
    this.maxLines,
  });

  static final _links = RegExp(r'refer to (\d+(?:-\d+)*)|<([A-Za-z][^<>]*?)>');

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: heading ? 16 : (muted ? 13.5 : 14.5),
      height: 1.45,
      fontWeight: heading ? FontWeight.w800 : (bold ? FontWeight.w600 : FontWeight.w400),
      color: muted ? Z.muted : Z.text,
    );
    final interactive = maxLines == null; // previews in lists stay plain taps
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _links.allMatches(text)) {
      final ruleRef = m.group(1);
      String? target;
      String shown;
      if (ruleRef != null) {
        target = book.byId.containsKey(ruleRef) || !ruleRef.contains('-') ? ruleRef : null;
        spans.addAll(_marked(text.substring(last, m.start), base));
        spans.add(TextSpan(text: 'refer to ', style: base));
        shown = ruleRef;
      } else {
        target = _keywordId(m.group(2)!);
        if (target == null) continue; // "<...>" that isn't a keyword
        if (m.group(0) == text.trim()) continue; // the heading "<Blocker>" itself
        spans.addAll(_marked(text.substring(last, m.start), base));
        shown = m.group(0)!;
      }
      final linkStyle = base.copyWith(
        color: Z.blue,
        fontWeight: FontWeight.w700,
        decoration: interactive ? TextDecoration.underline : null,
        decorationColor: Z.blue,
      );
      if (interactive && target != null) {
        final id = target;
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(onTap: () => openRule(context, book, id), child: Text(shown, style: linkStyle)),
        ));
      } else {
        spans.add(TextSpan(text: shown, style: linkStyle));
      }
      last = m.end;
    }
    spans.addAll(_marked(text.substring(last), base));
    return Text.rich(
      TextSpan(children: spans),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }

  /// "Security A. +1" → id of `<Security A.>`; "Blocker" → 16-5.
  String? _keywordId(String inner) {
    final name = inner.replaceAll(RegExp(r'\s*[+-]\s*\d+$'), '').trim().toLowerCase();
    for (final k in book.keywords) {
      final n = k.name.toLowerCase();
      if (n == name || name.startsWith('$n ')) return k.id;
    }
    return null;
  }

  List<InlineSpan> _marked(String s, TextStyle style) {
    final h = highlight?.trim();
    if (h == null || h.isEmpty || s.isEmpty) return [TextSpan(text: s, style: style)];
    final terms = SmartSearch.terms(h).expand((g) => g).where((t) => t.length >= 2).toList();
    if (terms.isEmpty) return [TextSpan(text: s, style: style)];
    final re = RegExp(terms.map(RegExp.escape).join('|'), caseSensitive: false);
    final out = <InlineSpan>[];
    var i = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > i) out.add(TextSpan(text: s.substring(i, m.start), style: style));
      out.add(TextSpan(
          text: s.substring(m.start, m.end),
          style: style.copyWith(backgroundColor: Z.gold.withValues(alpha: .28), color: Z.text)));
      i = m.end;
    }
    if (i < s.length) out.add(TextSpan(text: s.substring(i), style: style));
    return out;
  }
}

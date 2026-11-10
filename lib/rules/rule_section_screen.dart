import 'package:flutter/material.dart';

import '../theme.dart';
import 'rule_widgets.dart';
import 'rules_data.dart';

/// A rule with everything under it. Reached from chapters, keyword chips,
/// search results and "refer to" links.
class RuleSectionScreen extends StatelessWidget {
  final RulesBook book;
  final String id; // a rule id, or a chapter number such as "12"
  final String? highlight;

  const RuleSectionScreen({super.key, required this.book, required this.id, this.highlight});

  @override
  Widget build(BuildContext context) {
    final rules = book.section(id);
    final isChapter = !id.contains('-');
    final head = book.byId[id];
    final title = isChapter ? '$id. ${book.chapterTitle(id)}' : '$id ${head != null && head.isHeading ? head.text : ''}';
    final crumbs = isChapter ? <Rule>[] : book.ancestors(id);
    final chapter = id.split('-').first;

    return Scaffold(
      appBar: AppBar(
        title: Text(title.trim(), maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // Breadcrumb: chapter › parent headings, each tappable.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _crumb(context, '$chapter. ${book.chapterTitle(chapter)}', chapter, current: isChapter),
                if (chapterHebrew[chapter] != null)
                  Text(chapterHebrew[chapter]!, style: const TextStyle(color: Z.muted, fontSize: 12.5)),
                for (final c in crumbs.where((c) => c.id != chapter)) ...[
                  const Icon(Icons.chevron_right, size: 16, color: Z.muted),
                  _crumb(context, c.isHeading ? '${c.id} ${c.text}' : c.id, c.id),
                ],
              ]),
            ),
          ),
          if (rules.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('הסעיף לא נמצא בגרסה הנוכחית של החוקים.', style: TextStyle(color: Z.muted)),
            ),
          for (final r in rules)
            RuleTile(
              book: book,
              rule: r,
              highlight: highlight,
              indentFrom: isChapter ? 2 : (head?.depth ?? 1),
            ),
        ],
      ),
    );
  }

  Widget _crumb(BuildContext context, String text, String target, {bool current = false}) {
    return ActionChip(
      visualDensity: VisualDensity.compact,
      label: Text(text, style: TextStyle(fontSize: 12.5, color: current ? Z.gold : Z.text)),
      onPressed: current ? null : () => openRule(context, book, target),
    );
  }
}

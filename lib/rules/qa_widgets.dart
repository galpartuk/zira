import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'qa_data.dart';
import 'rule_widgets.dart';
import 'rules_data.dart';

/// A Q&A entry in a list: Q number, topic/card, question, first line of the answer.
class QaTile extends StatelessWidget {
  final RulesBook book;
  final QaBook qa;
  final QaEntry e;
  final String? highlight;

  const QaTile({super.key, required this.book, required this.qa, required this.e, this.highlight});

  @override
  Widget build(BuildContext context) {
    final color = e.isCard ? Z.coral : Z.win;
    final where = e.isCard
        ? e.cards.map((c) => '${c.no} ${c.name}').join(' · ')
        : '${e.category} › ${e.topic}';
    return Directionality(
      textDirection: TextDirection.ltr,
      child: InkWell(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => QaDetailScreen(book: book, qa: qa, e: e, highlight: highlight))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(6)),
              child: Text(e.label,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color, fontFeatures: Z.tabular)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(where,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: color.withValues(alpha: .9), fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                RichRuleText(book: book, text: e.q, highlight: highlight, maxLines: 4, bold: true),
                const SizedBox(height: 3),
                RichRuleText(book: book, text: e.a, highlight: highlight, maxLines: 2, muted: true),
              ]),
            ),
            BookmarkButton(id: e.key),
          ]),
        ),
      ),
    );
  }
}

class QaDetailScreen extends StatelessWidget {
  final RulesBook book;
  final QaBook qa;
  final QaEntry e;
  final String? highlight;

  const QaDetailScreen({super.key, required this.book, required this.qa, required this.e, this.highlight});

  @override
  Widget build(BuildContext context) {
    final color = e.isCard ? Z.coral : Z.win;
    final topicQa = e.isCard ? const <QaEntry>[] : qa.forTopic(e.topic).where((x) => x.id != e.id).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(e.isCard ? 'Card Q&A · ${e.label}' : 'Rule Q&A · ${e.label}', textDirection: TextDirection.ltr),
        actions: [BookmarkButton(id: e.key)],
      ),
      body: Directionality(
        textDirection: TextDirection.ltr,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (e.isCard)
                for (final c in e.cards)
                  ActionChip(
                    avatar: Icon(Icons.style_outlined, size: 16, color: color),
                    label: Text('${c.no} ${c.name}'),
                    onPressed: () => _openCard(context, c.no),
                  )
              else ...[
                Chip(label: Text(e.category)),
                if (e.topic.isNotEmpty) Chip(label: Text(e.topic, style: TextStyle(color: color))),
              ],
            ]),
            const SizedBox(height: 14),
            _block('Q', e.q, color),
            const SizedBox(height: 12),
            _block('A', e.a, Z.gold),
            if (e.related.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Related cards', style: TextStyle(color: Z.muted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final no in e.related)
                  ActionChip(label: Text(no), onPressed: () => _openCard(context, no)),
              ]),
            ],
            if (e.date.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text('Updated ${e.date} · official Q&A', style: const TextStyle(color: Z.muted, fontSize: 12.5)),
              ),
            if (topicQa.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('More about ${e.topic} (${topicQa.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 4),
              for (final x in topicQa.take(30)) QaTile(book: book, qa: qa, e: x),
            ],
          ],
        ),
      ),
    );
  }

  Widget _block(String tag, String text, Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Z.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tag, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(width: 12),
        Expanded(child: RichRuleText(book: book, text: text, highlight: highlight)),
      ]),
    );
  }

  /// Card Q&A for that card inside the app, or the official card page.
  void _openCard(BuildContext context, String no) {
    final list = qa.forCard(no);
    if (list.isEmpty) {
      launchUrl(Uri.parse('https://world.digimoncard.com/cardlist/?search=true&card_no=$no'),
          mode: LaunchMode.externalApplication);
      return;
    }
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => QaListScreen(book: book, qa: qa, title: no, entries: list, cardNo: no)));
  }
}

/// A plain list of Q&A entries (a category, a card, bookmarks...).
class QaListScreen extends StatelessWidget {
  final RulesBook book;
  final QaBook qa;
  final String title;
  final List<QaEntry> entries;
  final String? cardNo;

  const QaListScreen({super.key, required this.book, required this.qa, required this.title, required this.entries, this.cardNo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, textDirection: TextDirection.ltr)),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 32),
        itemCount: entries.length + (cardNo != null ? 1 : 0),
        itemBuilder: (c, i) {
          if (cardNo != null && i == entries.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse('https://world.digimoncard.com/cardlist/?search=true&card_no=$cardNo'),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new),
                label: Text('$cardNo באתר הרשמי'),
              ),
            );
          }
          return QaTile(book: book, qa: qa, e: entries[i]);
        },
      ),
    );
  }
}

/// Rule Q&A grouped by topic within one category ("Keyword Effects" → Blocker, Rush...).
class QaCategoryScreen extends StatelessWidget {
  final RulesBook book;
  final QaBook qa;
  final String category;

  const QaCategoryScreen({super.key, required this.book, required this.qa, required this.category});

  @override
  Widget build(BuildContext context) {
    final byTopic = <String, List<QaEntry>>{};
    for (final e in qa.rule.where((e) => e.category == category)) {
      byTopic.putIfAbsent(e.topic.isEmpty ? '—' : e.topic, () => []).add(e);
    }
    return Scaffold(
      appBar: AppBar(title: Text(category, textDirection: TextDirection.ltr)),
      body: Directionality(
        textDirection: TextDirection.ltr,
        child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          for (final t in byTopic.entries)
            ListTile(
              title: Text(t.key, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: Text('${t.value.length}', style: const TextStyle(color: Z.muted, fontFeatures: Z.tabular)),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => QaListScreen(book: book, qa: qa, title: '$category › ${t.key}', entries: t.value))),
            ),
        ]),
      ),
    );
  }
}

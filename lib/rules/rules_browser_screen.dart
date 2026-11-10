import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'rule_widgets.dart';
import 'rules_data.dart';

/// The Comprehensive Rules inside the app: search (English or Hebrew),
/// keyword chips, chapters, rules changed in this version, bookmarks.
class RulesBrowserScreen extends StatefulWidget {
  const RulesBrowserScreen({super.key});

  @override
  State<RulesBrowserScreen> createState() => _RulesBrowserScreenState();
}

class _RulesBrowserScreenState extends State<RulesBrowserScreen> {
  RulesBook? _book;
  final _q = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _newerOnline = false;

  @override
  void initState() {
    super.initState();
    RuleBookmarks.instance.load();
    RulesBook.load().then((b) {
      if (!mounted) return;
      setState(() => _book = b);
      _checkForUpdate(b);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  /// Asks Bandai's server when the PDF last changed. If it is newer than the
  /// copy built into the app, a banner offers the official PDF.
  Future<void> _checkForUpdate(RulesBook b) async {
    if (b.lastModifiedEpoch == null) return;
    try {
      final r = await http.head(Uri.parse(b.source)).timeout(const Duration(seconds: 8));
      final online = parseHttpDate(r.headers['last-modified']);
      if (online != null && online > b.lastModifiedEpoch! + 3600 && mounted) {
        setState(() => _newerOnline = true);
      }
    } catch (_) {
      // Offline is fine: the built-in copy still works.
    }
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = _book;
    return Scaffold(
      appBar: AppBar(
        title: const Text('חוקי דיג׳ימון — מלא'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _q,
              onChanged: _onQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'חיפוש: blocker, זיכרון, 11-5…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _q.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
      body: b == null
          ? const Center(child: CircularProgressIndicator())
          : (_query.isEmpty ? _home(b) : _results(b)),
    );
  }

  Widget _results(RulesBook b) {
    final hits = b.search(_query);
    if (hits.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'לא נמצא "$_query"',
        body: 'החוקים באנגלית. נסו מילה באנגלית (blocker, security) או מספר סעיף (11-5).',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: hits.length + 1,
      itemBuilder: (c, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(hits.length >= 300 ? '300+ תוצאות — כדאי לחדד' : '${hits.length} תוצאות',
                style: const TextStyle(color: Z.muted, fontWeight: FontWeight.w700)),
          );
        }
        final r = hits[i - 1];
        return RuleTile(
          book: b,
          rule: r,
          highlight: _query,
          showBreadcrumb: true,
          indentFrom: r.depth,
          onTap: () => openRule(context, b, r.id, highlight: _query),
        );
      },
    );
  }

  Widget _home(RulesBook b) {
    final changed = b.changedInLatest;
    return ListenableBuilder(
      listenable: RuleBookmarks.instance,
      builder: (context, _) {
        final marks = RuleBookmarks.instance.ids.where(b.byId.containsKey).toList()
          ..sort((x, y) => b.rules.indexOf(b.byId[x]!) - b.rules.indexOf(b.byId[y]!));
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (_newerOnline)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                decoration: BoxDecoration(
                  color: Z.gold.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Z.gold.withValues(alpha: .5)),
                ),
                child: Row(children: [
                  const Icon(Icons.new_releases_outlined, color: Z.gold),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('נראה שבאתר של Bandai יש קובץ חוקים חדש יותר מזה שבאפליקציה.',
                        style: TextStyle(fontSize: 13.5, height: 1.35)),
                  ),
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse(b.source), mode: LaunchMode.externalApplication),
                    child: const Text('PDF'),
                  ),
                ]),
              ),
            // Version card
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(children: [
                  const Icon(Icons.gavel_rounded, color: Z.blue, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Comprehensive Rules', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      Text('גרסה ${b.version} · ${b.updatedLabel} · ${b.rules.length} סעיפים',
                          style: const TextStyle(color: Z.muted, fontSize: 13)),
                    ]),
                  ),
                ]),
              ),
            ),
            if (changed.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Material(
                  color: Z.gold.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: const Icon(Icons.fiber_new_rounded, color: Z.gold),
                    title: Text('${changed.length} סעיפים עודכנו בגרסה ${b.version}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    trailing: const Icon(Icons.chevron_left, color: Z.gold),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                _RuleListScreen(title: 'עודכנו בגרסה ${b.version}', book: b, rules: changed))),
                  ),
                ),
              ),
            if (marks.isNotEmpty) ...[
              SectionTitle('סימניות', trailing: Pill('${marks.length}', color: Z.gold)),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  for (final id in marks)
                    RuleTile(
                        book: b,
                        rule: b.byId[id]!,
                        indentFrom: b.byId[id]!.depth,
                        showBreadcrumb: true,
                        onTap: () => openRule(context, b, id)),
                ]),
              ),
            ],
            SectionTitle('מילות מפתח (Keyword effects)', trailing: Pill('${b.keywords.length}', color: Z.blue)),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final k in b.keywords)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('<${k.name}>', style: const TextStyle(fontSize: 13)),
                    tooltip: k.summary,
                    onPressed: () => openRule(context, b, k.id),
                  ),
              ]),
            ),
            const SectionTitle('פרקים'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final e in b.chapters.entries)
                  ListTile(
                    dense: true,
                    leading: SizedBox(
                      width: 28,
                      child: Text(e.key,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Z.blue, fontFeatures: Z.tabular)),
                    ),
                    title: Text(chapterHebrew[e.key] ?? e.value,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    subtitle: Text(e.value, style: const TextStyle(color: Z.muted)),
                    trailing: Text('${b.section(e.key).length}',
                        style: const TextStyle(color: Z.muted, fontFeatures: Z.tabular)),
                    onTap: () => openRule(context, b, e.key),
                  ),
              ]),
            ),
            const SizedBox(height: 14),
            const Text(
              'החוקים נלקחו מקובץ ה-Comprehensive Rules הרשמי של Bandai ומוצגים באנגלית, כמו במקור. במקרה של ספק — המסמך הרשמי קובע.',
              style: TextStyle(color: Z.muted, fontSize: 12.5, height: 1.45),
            ),
          ],
        );
      },
    );
  }
}

class _RuleListScreen extends StatelessWidget {
  final String title;
  final RulesBook book;
  final List<Rule> rules;
  const _RuleListScreen({required this.title, required this.book, required this.rules});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(children: [
        for (final r in rules)
          RuleTile(
              book: book,
              rule: r,
              indentFrom: r.depth,
              showBreadcrumb: true,
              onTap: () => openRule(context, book, r.id)),
      ]),
    );
  }
}

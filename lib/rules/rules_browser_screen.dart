import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'qa_data.dart';
import 'qa_widgets.dart';
import 'rule_widgets.dart';
import 'rules_data.dart';
import 'smart_search.dart';

/// The Comprehensive Rules and the official Q&A inside the app.
/// One search box covers both (English or Hebrew, card numbers, rule numbers).
class RulesBrowserScreen extends StatefulWidget {
  const RulesBrowserScreen({super.key});

  @override
  State<RulesBrowserScreen> createState() => _RulesBrowserScreenState();
}

enum _Filter { all, rules, ruleQa, cardQa }

class _RulesBrowserScreenState extends State<RulesBrowserScreen> {
  RulesBook? _book;
  QaBook? _qa;
  SmartSearch? _search;
  final _q = TextEditingController();
  Timer? _debounce;
  String _query = '';
  SearchResult? _result;
  _Filter _filter = _Filter.all;
  bool _newerOnline = false;

  @override
  void initState() {
    super.initState();
    RuleBookmarks.instance.load();
    Future.wait([RulesBook.load(), QaBook.load()]).then((v) {
      if (!mounted) return;
      final b = v[0] as RulesBook, qa = v[1] as QaBook;
      setState(() {
        _book = b;
        _qa = qa;
        _search = SmartSearch(b, qa);
      });
      _checkForUpdate(b);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  /// Asks Bandai's server when the rules PDF last changed. If it is newer
  /// than the copy built into the app, a banner offers the official PDF.
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

  void _setQuery(String v) {
    _q.value = TextEditingValue(text: v, selection: TextSelection.collapsed(offset: v.length));
    _run(v);
  }

  void _run(String v) {
    final q = v.trim();
    setState(() {
      _query = q;
      _result = q.isEmpty ? null : _search?.run(q);
      _filter = _Filter.all;
    });
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) _run(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = _book, qa = _qa;
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
                hintText: 'חוקים + Q&A: blocker, זיכרון, BT24-001…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.close), onPressed: () => _setQuery('')),
              ),
            ),
          ),
        ),
      ),
      body: b == null || qa == null
          ? const Center(child: CircularProgressIndicator())
          : (_query.isEmpty ? _home(b, qa) : _results(b, qa)),
    );
  }

  // ---------------------------------------------------------------- results

  Widget _results(RulesBook b, QaBook qa) {
    final res = _result;
    if (res == null) return const SizedBox();
    if (res.hits.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'לא נמצא "$_query"',
        body: 'נסו מילה באנגלית (blocker, security), מילה בעברית שמופיעה ברשימה (זיכרון, חוסם), מספר סעיף (11-5) או מספר קלף (BT24-001).',
      );
    }
    final shown = res.hits.where((h) => switch (_filter) {
          _Filter.all => true,
          _Filter.rules => h.kind == HitKind.rule,
          _Filter.ruleQa => h.kind == HitKind.ruleQa,
          _Filter.cardQa => h.kind == HitKind.cardQa,
        }).toList();

    Widget chip(_Filter f, String label, int n) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: ChoiceChip(
            label: Text('$label $n'),
            selected: _filter == f,
            showCheckmark: false,
            selectedColor: Z.gold,
            labelStyle: TextStyle(color: _filter == f ? Z.ink : Z.text, fontWeight: FontWeight.w700, fontFeatures: Z.tabular),
            onSelected: n == 0 && f != _Filter.all ? null : (_) => setState(() => _filter = f),
          ),
        );

    return Column(children: [
      SizedBox(
        height: 50,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 8, 16, 2), children: [
          chip(_Filter.all, 'הכל', res.hits.length),
          chip(_Filter.rules, 'חוקים', res.count(HitKind.rule)),
          chip(_Filter.ruleQa, 'Q&A חוקים', res.count(HitKind.ruleQa)),
          chip(_Filter.cardQa, 'Q&A קלפים', res.count(HitKind.cardQa)),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 32),
          itemCount: shown.length + 1,
          itemBuilder: (c, i) {
            if (i == 0) return _spotlight(b, qa, res);
            final h = shown[i - 1];
            if (h.kind == HitKind.rule) {
              final r = h.rule!;
              return RuleTile(
                book: b,
                rule: r,
                highlight: _query,
                showBreadcrumb: true,
                indentFrom: r.depth,
                onTap: () => openRule(context, b, r.id, highlight: _query),
              );
            }
            return QaTile(book: b, qa: qa, e: h.qa!, highlight: _query);
          },
        ),
      ),
    ]);
  }

  /// Shown above the results when the query names a keyword or a card.
  Widget _spotlight(RulesBook b, QaBook qa, SearchResult res) {
    final k = res.keyword;
    if (res.cardNo != null) {
      final names = {for (final h in res.hits) ...h.qa!.cards.where((c) => QaBook.canonicalCardNo(c.no).startsWith(QaBook.canonicalCardNo(res.cardNo!))).map((c) => '${c.no} ${c.name}')};
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          names.length == 1 ? 'Q&A לקלף ${names.first}' : '${res.hits.length} שאלות על ${names.length} קלפים (${res.cardNo})',
          textDirection: TextDirection.rtl,
          style: const TextStyle(color: Z.coral, fontWeight: FontWeight.w800),
        ),
      );
    }
    if (k == null) return const SizedBox(height: 4);
    final topicQa = qa.forTopic(k.name);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: Z.blue.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Z.blue.withValues(alpha: .45)),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('<${k.name}>', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Z.blue)),
          const SizedBox(height: 4),
          Text(k.summary, style: const TextStyle(height: 1.4)),
          const SizedBox(height: 4),
          Wrap(spacing: 4, children: [
            TextButton.icon(
              onPressed: () => openRule(context, b, k.id),
              icon: const Icon(Icons.gavel_rounded, size: 18),
              label: Text('Rules ${k.id}'),
            ),
            if (topicQa.isNotEmpty)
              TextButton.icon(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => QaListScreen(book: b, qa: qa, title: 'Q&A · <${k.name}>', entries: topicQa))),
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: Text('${topicQa.length} Q&A'),
              ),
          ]),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- home

  Widget _home(RulesBook b, QaBook qa) {
    final changed = b.changedInLatest;
    return ListenableBuilder(
      listenable: RuleBookmarks.instance,
      builder: (context, _) {
        final marks = RuleBookmarks.instance.ids.where((id) => b.byId.containsKey(id) || qa.byKey.containsKey(id)).toList();
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
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(children: [
                  const Icon(Icons.gavel_rounded, color: Z.blue, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Comprehensive Rules + Q&A', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      Text(
                          'חוקים ${b.version} (${b.updatedLabel}) · ${b.rules.length} סעיפים · ${qa.rule.length + qa.card.length} שאלות',
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
                    if (b.byId[id] != null)
                      RuleTile(
                          book: b,
                          rule: b.byId[id]!,
                          indentFrom: b.byId[id]!.depth,
                          showBreadcrumb: true,
                          onTap: () => openRule(context, b, id))
                    else
                      QaTile(book: b, qa: qa, e: qa.byKey[id]!),
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
                    onPressed: () => _setQuery(k.name),
                  ),
              ]),
            ),
            SectionTitle('שאלות ותשובות רשמיות (Q&A)',
                trailing: Pill('${qa.rule.length + qa.card.length}', color: Z.win)),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final e in qa.ruleCategories.entries)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.forum_outlined, color: Z.win),
                    title: Text(e.key, textDirection: TextDirection.ltr, textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    trailing: Text('${e.value}', style: const TextStyle(color: Z.muted, fontFeatures: Z.tabular)),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => QaCategoryScreen(book: b, qa: qa, category: e.key))),
                  ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.style_outlined, color: Z.coral),
                  title: const Text('Q&A לפי קלף', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  subtitle: Text('${qa.card.length} שאלות. הקלידו מספר קלף בחיפוש, למשל BT24-001',
                      style: const TextStyle(color: Z.muted)),
                  onTap: () => _setQuery('BT24-001'),
                ),
              ]),
            ),
            const SectionTitle('פרקים בחוקים'),
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
            Text(
              'מקור: Comprehensive Rules ו-Q&A רשמיים של Bandai (באנגלית, כמו במקור). ה-Q&A נאסף ב-${qa.fetched}. במקרה של ספק — האתר הרשמי קובע.',
              style: const TextStyle(color: Z.muted, fontSize: 12.5, height: 1.45),
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

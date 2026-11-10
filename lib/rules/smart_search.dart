import 'qa_data.dart';
import 'rules_data.dart';

/// One search across the Comprehensive Rules, rule Q&A and card Q&A.
enum HitKind { rule, ruleQa, cardQa }

class Hit {
  final HitKind kind;
  final Rule? rule;
  final QaEntry? qa;
  final double score;
  const Hit(this.kind, this.score, {this.rule, this.qa});
}

class SearchResult {
  final String query;
  final List<Hit> hits;
  final RuleKeyword? keyword; // query names a keyword effect → spotlight
  final String? cardNo; // query is a card number / set code
  const SearchResult(this.query, this.hits, {this.keyword, this.cardNo});

  int count(HitKind k) => hits.where((h) => h.kind == k).length;
}

/// English shorthand players use → what the documents say.
const Map<String, List<String>> englishAliases = {
  'sec': ['security'],
  'evo': ['digivol'],
  'evolve': ['digivol'],
  'evolution': ['digivol'],
  'egg': ['digi-egg'],
  'ko': ['delet'],
  'kill': ['delet'],
  'destroy': ['delet'],
  'opp': ['opponent'],
  'source': ['digivolution card'],
  'sources': ['digivolution card'],
  'inherit': ['inherited'],
  'ess': ['inherited'],
  'tap': ['suspend'],
  'untap': ['unsuspend'],
  'graveyard': ['trash'],
  'discard': ['trash'],
  'mem': ['memory'],
};

/// Extra Hebrew words that show up in Q&A questions.
const Map<String, List<String>> hebrewQaAliases = {
  'opponent': ['יריב', 'היריב', 'אופוננט'],
  'activat': ['הפעלה', 'להפעיל', 'מופעל'],
  'trigger': ['טריגר', 'מופעל'],
  'simultaneous': ['בו זמנית', 'בבת אחת', 'ביחד'],
  'order': ['סדר'],
  'end of turn': ['סוף תור'],
  'start of turn': ['תחילת תור'],
  'when digivolving': ['כשמתפתח'],
  'on play': ['כשנכנס', 'און פליי'],
  'on deletion': ['כשנמחק'],
};

final _cardNo = RegExp(r'^(bt|ex|st|p|rb|ad|lm)\s*\d*\s*-?\s*\d*$', caseSensitive: false);

class SmartSearch {
  final RulesBook rules;
  final QaBook qa;
  late final Map<String, String> _ruleLow = {for (final r in rules.rules) r.id: r.text.toLowerCase()};

  SmartSearch(this.rules, this.qa);

  /// Each query word → alternatives that must appear (any of them).
  static List<List<String>> terms(String query) {
    final out = <List<String>>[];
    for (final raw in query.toLowerCase().split(RegExp(r'\s+'))) {
      final w = raw.replaceAll(RegExp(r'^[^\w֐-׿<-]+|[^\w֐-׿>-]+$'), '');
      if (w.isEmpty) continue;
      final alts = <String>{};
      if (RegExp(r'[֐-׿]').hasMatch(w)) {
        alts.addAll(RulesBook.searchTerms(w).expand((g) => g));
        final clean = w.replaceAll(RegExp('[״"׳\']'), '');
        hebrewQaAliases.forEach((en, list) {
          for (final a in list) {
            if (a == clean || (clean.length >= 3 && a.startsWith(clean))) alts.add(en);
          }
        });
        // An unknown Hebrew word can't match English text; ignore it rather
        // than returning nothing.
        alts.removeWhere((a) => RegExp(r'[֐-׿]').hasMatch(a));
        if (alts.isEmpty) continue;
      } else {
        final word = w.replaceAll(RegExp('[<>]'), '');
        alts.add(stem(word));
        for (final e in englishAliases[word] ?? const <String>[]) {
          alts.add(e);
        }
      }
      out.add(alts.toList());
    }
    return out;
  }

  /// Crude English stemmer: enough that "attacks" finds "attacking".
  static String stem(String w) {
    if (w.length <= 4) return w;
    for (final suf in ['ing', 'ed', 'es', 's']) {
      if (w.endsWith(suf) && w.length - suf.length >= 4) return w.substring(0, w.length - suf.length);
    }
    return w;
  }

  /// Score of [alts] in [text]: 0 if absent; more for whole-word hits.
  static double _hit(String text, List<String> alts) {
    var best = 0.0;
    for (final a in alts) {
      final i = text.indexOf(a);
      if (i < 0) continue;
      final before = i == 0 || !RegExp(r'[a-z0-9]').hasMatch(text[i - 1]);
      final end = i + a.length;
      final after = end >= text.length || !RegExp(r'[a-z0-9]').hasMatch(text[end]);
      final s = 1.0 + (before ? .5 : 0) + (after ? .3 : 0);
      if (s > best) best = s;
    }
    return best;
  }

  SearchResult run(String query, {int limit = 400}) {
    final q = query.trim();
    if (q.isEmpty) return SearchResult(q, const []);

    // Rule number, e.g. "11-5"
    if (RegExp(r'^\d+(-\d+)*$').hasMatch(q)) {
      final hits = rules.search(q).map((r) => Hit(HitKind.rule, 10, rule: r)).toList();
      return SearchResult(q, hits);
    }

    // Card number or set code, e.g. "BT24-001", "bt24 1", "EX13"
    if (_cardNo.hasMatch(q) && RegExp(r'\d').hasMatch(q)) {
      final no = _normalCardNo(q);
      final hits = qa.forCard(no).map((e) => Hit(HitKind.cardQa, 10, qa: e)).toList();
      if (hits.isNotEmpty) return SearchResult(q, hits, cardNo: no);
    }

    final groups = terms(q);
    if (groups.isEmpty) return SearchResult(q, const []);

    final hits = <Hit>[];
    // Rules: heading lines weigh more.
    for (final r in rules.rules) {
      final t = _ruleLow[r.id]!;
      var total = 0.0;
      for (final g in groups) {
        final s = _hit(t, g);
        if (s == 0) {
          total = -1;
          break;
        }
        total += s * (r.isHeading ? 4 : 1.2);
      }
      if (total > 0) {
        if (r.text.startsWith('<') && r.isHeading) total += 6; // keyword definition
        hits.add(Hit(HitKind.rule, total, rule: r));
      }
    }
    // Q&A: title (topic / card) > question > answer.
    for (final e in [...qa.rule, ...qa.card]) {
      var total = 0.0;
      for (final g in groups) {
        final s = 3.5 * _hit(e.titleLow, g) + 2.0 * _hit(e.qLow, g) + 0.8 * _hit(e.aLow, g);
        if (s == 0) {
          total = -1;
          break;
        }
        total += s;
      }
      if (total > 0) hits.add(Hit(e.isCard ? HitKind.cardQa : HitKind.ruleQa, e.isCard ? total * .9 : total, qa: e));
    }
    hits.sort((a, b) => b.score.compareTo(a.score));

    return SearchResult(q, hits.take(limit).toList(), keyword: _keyword(q, groups));
  }

  RuleKeyword? _keyword(String q, List<List<String>> groups) {
    final plain = q.toLowerCase().replaceAll(RegExp('[<>]'), '').trim();
    for (final k in rules.keywords) {
      final n = k.name.toLowerCase();
      if (n == plain || stem(n) == stem(plain)) return k;
    }
    if (groups.length == 1) {
      for (final k in rules.keywords) {
        if (groups.first.contains(k.name.toLowerCase())) return k;
      }
    }
    return null;
  }

  /// "bt24 1" → "BT24-1", "p194" → "P-194", "EX13" → "EX13".
  static String _normalCardNo(String q) {
    final m = RegExp(r'^([a-z]+)\s*(\d*)\s*-?\s*(\d+)?$', caseSensitive: false).firstMatch(q.trim());
    if (m == null) return q.toUpperCase();
    final prefix = m.group(1)!.toUpperCase();
    final setNo = m.group(2) ?? '';
    final num = m.group(3);
    if (setNo.isEmpty) return num == null ? prefix : '$prefix-$num';
    return num == null ? '$prefix$setNo' : '$prefix$setNo-$num';
  }

  static String normalCardNo(String q) => _normalCardNo(q);
}

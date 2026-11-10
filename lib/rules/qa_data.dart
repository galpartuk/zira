import 'dart:convert';

import 'package:flutter/services.dart';

/// Official Q&A from world.digimoncard.com/rule/, collected by
/// tool/build_qa.py into assets/rules/qa.json.
class QaCard {
  final String no; // "BT24-001"
  final String name; // "Gigimon"
  const QaCard(this.no, this.name);
}

class QaEntry {
  final int id; // Q number on the official site
  final String q;
  final String a;
  final bool isCard;
  final String category; // rule Q&A: "Keyword Effects"; card Q&A: set code
  final String topic; // rule Q&A: "Blocker"; card Q&A: first card's name
  final List<QaCard> cards;
  final List<String> related; // related card numbers
  final String date;

  // Lower-cased copies for searching.
  late final String qLow = q.toLowerCase();
  late final String aLow = a.toLowerCase();
  late final String titleLow = (isCard ? cards.map((c) => '${c.no} ${c.name}').join(' ') : topic).toLowerCase();

  QaEntry({
    required this.id,
    required this.q,
    required this.a,
    required this.isCard,
    required this.category,
    required this.topic,
    required this.cards,
    required this.related,
    required this.date,
  });

  String get key => 'q:${isCard ? 'c' : 'r'}$id';
  String get label => 'Q${'$id'}';
}

class QaBook {
  final String source;
  final String fetched;
  final List<QaEntry> rule;
  final List<QaEntry> card;
  final Map<String, QaEntry> byKey;

  QaBook._(this.source, this.fetched, this.rule, this.card)
      : byKey = {for (final e in [...rule, ...card]) e.key: e};

  factory QaBook.fromJson(Map<String, dynamic> j) {
    final rule = (j['rule'] as List)
        .map((e) => QaEntry(
              id: e['id'] as int,
              q: e['q'] as String,
              a: e['a'] as String,
              isCard: false,
              category: e['cat'] as String,
              topic: e['sub'] as String,
              cards: const [],
              related: const [],
              date: e['date'] as String? ?? '',
            ))
        .toList();
    final card = (j['card'] as List).map((e) {
      final cards = (e['cards'] as List).map((c) => QaCard(c['no'] as String, c['name'] as String)).toList();
      return QaEntry(
        id: e['id'] as int,
        q: e['q'] as String,
        a: e['a'] as String,
        isCard: true,
        category: e['set'] as String? ?? '',
        topic: cards.isEmpty ? '' : cards.first.name,
        cards: cards,
        related: (e['rel'] as List).cast<String>(),
        date: e['date'] as String? ?? '',
      );
    }).toList();
    return QaBook._(j['source'] as String, j['fetched'] as String, rule, card);
  }

  static QaBook? _cache;
  static Future<QaBook> load() async => _cache ??=
      QaBook.fromJson(jsonDecode(await rootBundle.loadString('assets/rules/qa.json')) as Map<String, dynamic>);

  /// Rule Q&A categories in site order, with counts.
  Map<String, int> get ruleCategories {
    final m = <String, int>{};
    for (final e in rule) {
      m[e.category] = (m[e.category] ?? 0) + 1;
    }
    return m;
  }

  /// Rule Q&A filed under a topic, e.g. "Blocker" or "Security A.".
  List<QaEntry> forTopic(String topic) {
    final t = _norm(topic);
    return rule.where((e) => _norm(e.topic) == t).toList();
  }

  /// Card Q&A for a card number or set prefix ("BT24-001", "BT24").
  /// Leading zeros don't matter: "bt1-1", "BT1-001" and "BT01-001" are the same card.
  List<QaEntry> forCard(String no) {
    final n = canonicalCardNo(no);
    final setOnly = !n.contains('-') || RegExp(r'^[A-Z]+-?$').hasMatch(n);
    return card.where((e) {
      return e.cards.any((c) {
        final k = canonicalCardNo(c.no);
        return k == n || (setOnly && k.startsWith('$n-'));
      });
    }).toList();
  }

  static String canonicalCardNo(String s) => s
      .toUpperCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAllMapped(RegExp(r'\d+'), (m) => int.parse(m[0]!).toString());

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[<>]'), '').trim();
}

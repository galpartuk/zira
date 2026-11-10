import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zira/rules/qa_data.dart';
import 'package:zira/rules/rules_data.dart';
import 'package:zira/rules/smart_search.dart';

void main() {
  late RulesBook book;
  late QaBook qa;
  late SmartSearch s;

  setUpAll(() {
    book = RulesBook.fromJson(
        jsonDecode(File('assets/rules/comprehensive.json').readAsStringSync()) as Map<String, dynamic>);
    qa = QaBook.fromJson(jsonDecode(File('assets/rules/qa.json').readAsStringSync()) as Map<String, dynamic>);
    s = SmartSearch(book, qa);
  });

  test('Q&A data is complete and clean', () {
    expect(qa.rule.length, greaterThan(500));
    expect(qa.card.length, greaterThan(3000));
    for (final e in [...qa.rule, ...qa.card]) {
      expect(e.q, isNotEmpty, reason: e.label);
      expect(e.a, isNotEmpty, reason: e.label);
      expect(e.q.contains('<span') || e.a.contains('<br'), isFalse, reason: e.label);
    }
    expect(qa.card.every((e) => e.cards.isNotEmpty), isTrue);
    expect(qa.ruleCategories.keys, containsAll(['Basic Rules', 'Keyword Effects']));
  });

  test('keyword query: spotlight + definition first + its Q&A', () {
    final r = s.run('blocker');
    expect(r.keyword?.name, 'Blocker');
    expect(r.hits.first.rule?.text, '<Blocker>');
    expect(r.count(HitKind.ruleQa), greaterThan(0));
    expect(qa.forTopic('Blocker'), isNotEmpty);
  });

  test('hebrew query reaches rules and Q&A', () {
    final r = s.run('חוסם');
    expect(r.count(HitKind.rule), greaterThan(0));
    expect(r.count(HitKind.ruleQa), greaterThan(0));
    final r2 = s.run('זיכרון יריב');
    expect(r2.hits, isNotEmpty);
  });

  test('stemming and shorthand', () {
    expect(SmartSearch.stem('attacks'), 'attack');
    expect(SmartSearch.stem('digivolving'), 'digivolv');
    expect(SmartSearch.terms('sec')[0], containsAll(['sec', 'security']));
    // "attacks" finds text that only says "attacking".
    expect(s.run('attacks').hits.length, greaterThanOrEqualTo(s.run('attack').hits.length * 0.9));
  });

  test('card numbers: zero padding does not matter', () {
    expect(QaBook.canonicalCardNo('BT1-001'), 'BT1-1');
    expect(QaBook.canonicalCardNo('bt01-1'), 'BT1-1');
    final a = s.run('BT24-001'), b = s.run('bt24 1');
    expect(a.hits, isNotEmpty);
    expect(a.cardNo, isNotNull);
    expect(b.hits.map((h) => h.qa!.id), a.hits.map((h) => h.qa!.id));
    expect(a.hits.every((h) => h.kind == HitKind.cardQa), isTrue);
    // A whole set.
    expect(s.run('BT24').hits.length, greaterThan(a.hits.length));
  });

  test('card names are searchable', () {
    final r = s.run('gigimon');
    expect(r.count(HitKind.cardQa), greaterThan(0));
  });

  test('rule numbers still work', () {
    expect(s.run('11-5').hits.first.rule?.id, '11-5');
  });

  test('unknown hebrew words are ignored instead of killing the search', () {
    expect(s.run('blocker שלום').hits.length, s.run('blocker').hits.length);
  });
}

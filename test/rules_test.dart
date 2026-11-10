import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zira/rules/rules_data.dart';

void main() {
  late RulesBook book;
  setUpAll(() {
    book = RulesBook.fromJson(
        jsonDecode(File('assets/rules/comprehensive.json').readAsStringSync()) as Map<String, dynamic>);
  });

  test('loads the whole rulebook', () {
    expect(book.version, isNotEmpty);
    expect(book.rules.length, greaterThan(1000));
    expect(book.chapters.length, 18);
    expect(book.keywords.length, greaterThan(40));
  });

  test('every cross reference and keyword points at a real rule', () {
    for (final r in book.rules) {
      for (final ref in r.refs) {
        expect(book.byId.containsKey(ref), isTrue, reason: '${r.id} -> $ref');
      }
    }
    for (final k in book.keywords) {
      expect(book.byId.containsKey(k.id), isTrue, reason: k.name);
      expect(k.summary, isNotEmpty, reason: k.name);
    }
  });

  test('no PDF extraction artifacts in the text', () {
    final repeatedRef = RegExp(r'refer to (\d+(?:-\d+)*)[^)]*\)\1(?![\d-])');
    final spacedHyphen = RegExp(r'[a-z] -[a-z]');
    for (final r in book.rules) {
      expect(repeatedRef.hasMatch(r.text), isFalse, reason: r.id);
      expect(spacedHyphen.hasMatch(r.text), isFalse, reason: r.id);
    }
    expect(book.search('blocker').first.text, '<Blocker>');
  });

  test('english search', () {
    final hits = book.search('blocker');
    expect(hits.first.id, '16-5'); // the <Blocker> heading comes first
    expect(book.search('blocker persistent').any((r) => r.id == '16-5-2'), isTrue);
  });

  test('hebrew search goes through the aliases', () {
    expect(book.search('חוסם').any((r) => r.id == '16-5'), isTrue);
    expect(book.search('זיכרון').any((r) => r.id == '4-1'), isTrue);
    expect(BookTerms.of('ממורי עלות'), [
      ['memory'],
      ['cost']
    ]);
  });

  test('rule number search and sections', () {
    expect(book.search('16-5').first.id, '16-5');
    final sec = book.section('16-5');
    expect(sec.first.id, '16-5');
    expect(sec.every((r) => r.id == '16-5' || r.id.startsWith('16-5-')), isTrue);
    expect(book.ancestors('16-5-2').map((r) => r.id), ['16', '16-5'].where(book.byId.containsKey));
  });

  test('rules changed in the latest version are marked', () {
    expect(book.changedInLatest, isNotEmpty);
    expect(book.changedInLatest.every((r) => r.changedIn == book.version), isTrue);
  });

  test('http date parsing for the update check', () {
    expect(parseHttpDate('Fri, 23 Oct 2026 06:10:49 GMT'), DateTime.utc(2026, 10, 23, 6, 10, 49).millisecondsSinceEpoch ~/ 1000);
    expect(parseHttpDate('nonsense'), isNull);
  });
}

class BookTerms {
  static List<List<String>> of(String q) => RulesBook.searchTerms(q);
}

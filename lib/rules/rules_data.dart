import 'dart:convert';

import 'package:flutter/services.dart';

/// The Digimon Comprehensive Rules, parsed from Bandai's PDF by
/// tool/build_rules.py into assets/rules/comprehensive.json.
class Rule {
  final String id; // "16-5-2"
  final String text;
  final String? changedIn; // rules version that last changed it

  Rule(this.id, this.text, this.changedIn);

  int get depth => '-'.allMatches(id).length + 1;
  String get chapter => id.split('-').first;

  /// Short label lines such as "4-1. Memory" act as headings.
  bool get isHeading => text.length < 70 && !text.endsWith('.') && !text.contains('. ');

  static final refPattern = RegExp(r'refer to (\d+(?:-\d+)*)');
  List<String> get refs => refPattern.allMatches(text).map((m) => m.group(1)!).toList();
}

class RuleKeyword {
  final String name; // "Blocker"
  final String id; // "16-5"
  final String summary;
  RuleKeyword(this.name, this.id, this.summary);
}

class RulesBook {
  final String title;
  final String version;
  final String updated; // "2026/09/18"
  final String source;
  final int? lastModifiedEpoch;
  final Map<String, String> chapters;
  final List<RuleKeyword> keywords;
  final List<Rule> rules;
  final Map<String, Rule> byId;

  RulesBook._(this.title, this.version, this.updated, this.source, this.lastModifiedEpoch, this.chapters,
      this.keywords, this.rules)
      : byId = {for (final r in rules) r.id: r};

  factory RulesBook.fromJson(Map<String, dynamic> j) => RulesBook._(
        j['title'] as String,
        j['version'] as String,
        j['updated'] as String,
        j['source'] as String,
        j['lastModifiedEpoch'] as int?,
        (j['chapters'] as Map).map((k, v) => MapEntry(k as String, v as String)),
        (j['keywords'] as List).map((e) => RuleKeyword(e['name'] as String, e['id'] as String, e['sum'] as String)).toList(),
        (j['rules'] as List).map((e) => Rule(e['id'] as String, e['t'] as String, e['v'] as String?)).toList(),
      );

  static RulesBook? _cache;
  static Future<RulesBook> load() async {
    return _cache ??= RulesBook.fromJson(
        jsonDecode(await rootBundle.loadString('assets/rules/comprehensive.json')) as Map<String, dynamic>);
  }

  /// "18.09.2026"
  String get updatedLabel {
    final p = updated.split('/');
    return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : updated;
  }

  List<Rule> get changedInLatest => rules.where((r) => r.changedIn == version).toList();

  /// The rule and everything under it, in document order.
  List<Rule> section(String id) => rules.where((r) => r.id == id || r.id.startsWith('$id-')).toList();

  /// Parent rules from the chapter down, not including [id] itself.
  List<Rule> ancestors(String id) {
    final parts = id.split('-');
    return [
      for (var i = 1; i < parts.length; i++)
        if (byId[parts.take(i).join('-')] != null) byId[parts.take(i).join('-')]!
    ];
  }

  /// Chapter number → its rules as a pseudo-heading when the chapter itself
  /// has no rule line ("1. Game Overview" is a TOC entry, not a rule).
  String chapterTitle(String chapter) => chapters[chapter] ?? 'Chapter $chapter';

  // ---------------------------------------------------------------- search

  /// Every query word must match. Hebrew words are translated through
  /// [hebrewAliases]; "16-5" style queries match rule numbers.
  List<Rule> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    if (RegExp(r'^\d+(-\d+)*$').hasMatch(q)) {
      return rules.where((r) => r.id == q || r.id.startsWith('$q-')).take(300).toList();
    }
    final groups = searchTerms(q);
    final hits = <Rule>[];
    for (final r in rules) {
      final t = r.text.toLowerCase();
      if (groups.every((alts) => alts.any(t.contains))) hits.add(r);
    }
    // Keyword definitions ("<Blocker>") first, then headings, then document order.
    int rank(Rule r) => r.text.startsWith('<') && r.isHeading ? 0 : (r.isHeading ? 1 : 2);
    hits.sort((a, b) {
      final ha = rank(a), hb = rank(b);
      if (ha != hb) return ha - hb;
      return rules.indexOf(a) - rules.indexOf(b);
    });
    return hits.take(300).toList();
  }

  /// Query → list of alternatives per word (English terms, lower case).
  static List<List<String>> searchTerms(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return [
      for (final w in words)
        if (RegExp(r'[֐-׿]').hasMatch(w)) _translate(w) else [w]
    ].where((g) => g.isNotEmpty).toList();
  }

  static List<String> _translate(String he) {
    final w = he.replaceAll(RegExp('[״"׳\']'), '');
    final out = <String>{};
    hebrewAliases.forEach((en, list) {
      for (final a in list) {
        final x = a.replaceAll(RegExp('[״"׳\']'), '');
        if (x == w || (w.length >= 3 && (x.startsWith(w) || w.startsWith(x)))) out.add(en);
      }
    });
    return out.isEmpty ? [w] : out.toList();
  }
}

/// English search term → Hebrew words people actually use at the table.
const Map<String, List<String>> hebrewAliases = {
  'memory': ['זיכרון', 'ממורי', 'מד זיכרון'],
  'security': ['סקיוריטי', 'מגן', 'מגנים', 'אבטחה'],
  'trash': ['טראש', 'אשפה', 'זבל', 'מחסנית זבל'],
  'breeding': ['גידול', 'ברידינג', 'אזור גידול'],
  'digi-egg': ['ביצה', 'ביצים', 'דיגיאג'],
  'hatch': ['בקיעה', 'לבקוע', 'האצ'],
  'digivol': ['התפתחות', 'דיגיבולב', 'דיגיבולושן', 'אבולוציה', 'להתפתח'],
  'deck': ['חפיסה', 'דק'],
  'hand': ['יד'],
  'draw': ['שליפה', 'משיכה', 'דרואו', 'לשלוף'],
  'mulligan': ['מוליגן', 'החלפת יד'],
  'suspend': ['השעיה', 'סאספנד', 'לסובב', 'מסובב', 'מושעה'],
  'unsuspend': ['אנסאספנד', 'ליישר', 'יישור'],
  'delet': ['מחיקה', 'למחוק', 'נמחק', 'דליט'],
  'attack': ['התקפה', 'לתקוף', 'תקיפה', 'אטאק'],
  'block': ['חסימה', 'לחסום', 'חוסם', 'בלוק', 'בלוקר'],
  'battle': ['קרב', 'באטל'],
  'tamer': ['טיימר', 'מאלף'],
  'option': ['אופציה', 'אופשן'],
  'effect': ['אפקט', 'אפקטים', 'יכולת'],
  'inherited': ['מורש', 'תורשה', 'אינהריט', 'בירושה'],
  'cost': ['עלות', 'מחיר'],
  'level': ['רמה', 'לבל'],
  'dp': ['כוח', 'די פי'],
  'turn': ['תור', 'תורות'],
  'first player': ['מתחיל', 'שחקן ראשון'],
  'token': ['טוקן', 'אסימון'],
  'link': ['לינק', 'קישור'],
  'play': ['לשחק', 'הנחה', 'להניח'],
  'recovery': ['ריקברי', 'שחזור'],
  'piercing': ['פירסינג', 'חודר'],
  'rush': ['ראש', 'הסתערות'],
  'jamming': ['גאמינג', 'ג׳אמינג'],
  'reboot': ['ריבוט'],
  'retaliation': ['נקמה', 'רטליאיישן'],
  'blitz': ['בליץ'],
  'evade': ['התחמקות', 'איבייד'],
  'barrier': ['מחסום', 'בארייר'],
  'raid': ['ריד', 'פשיטה'],
  'vortex': ['וורטקס', 'מערבולת'],
  'win': ['ניצחון', 'לנצח'],
  'lose': ['הפסד', 'להפסיד'],
};

/// Hebrew chapter names shown next to Bandai's English titles.
const chapterHebrew = {
  '1': 'סקירת המשחק',
  '2': 'מידע על הקלף',
  '3': 'אזורי המשחק',
  '4': 'מונחי יסוד',
  '5': 'הכנה למשחק',
  '6': 'מהלך המשחק',
  '7': 'הנחת קלף',
  '8': 'דיג׳יבולושן',
  '9': 'שימוש בקלפים',
  '10': 'לינק',
  '11': 'התקפה',
  '12': 'חסימה',
  '13': 'בדיקות סקיוריטי',
  '14': 'קרבות',
  '15': 'חוקי אפקטים',
  '16': 'מילות מפתח',
  '17': 'בדיקות חוקים',
  '18': 'מידע נוסף',
};

/// Parses an HTTP date ("Fri, 23 Oct 2026 06:10:49 GMT") to epoch seconds.
int? parseHttpDate(String? s) {
  if (s == null) return null;
  final m = RegExp(r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2})').firstMatch(s);
  if (m == null) return null;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final mon = months.indexOf(m.group(2)!) + 1;
  if (mon == 0) return null;
  return DateTime.utc(int.parse(m.group(3)!), mon, int.parse(m.group(1)!), int.parse(m.group(4)!),
              int.parse(m.group(5)!), int.parse(m.group(6)!))
          .millisecondsSinceEpoch ~/
      1000;
}

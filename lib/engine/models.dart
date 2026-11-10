import 'dart:math';

/// Data model for a tournament. Everything here is plain data + JSON; the
/// logic lives in the other engine files so it can be unit-tested headless.

final _rng = Random();

String newId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(10, (_) => chars[_rng.nextInt(chars.length)]).join();
}

enum TFormat { swiss, roundRobin }

enum Stage { swiss, top }

/// How a match ended. [doubleLoss] is no longer offered in the UI (time-outs
/// are reported as a 0-0 draw) but stays so old saved results still load.
enum Outcome { p1, p2, draw, doubleLoss }

class Player {
  final String id;
  String name;
  bool dropped;

  /// Fixed random number used as the last tiebreaker ("decided randomly").
  final int tieRand;

  Player({required this.id, required this.name, this.dropped = false, int? tieRand})
      : tieRand = tieRand ?? _rng.nextInt(1 << 30);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'dropped': dropped, 'tieRand': tieRand};

  factory Player.fromJson(Map<String, dynamic> j) => Player(
        id: j['id'] as String,
        name: j['name'] as String,
        dropped: j['dropped'] as bool? ?? false,
        tieRand: j['tieRand'] as int?,
      );
}

class MatchResult {
  final Outcome outcome;

  /// Game wins (best-of-3). For best-of-1 these are 1-0 / 0-1 / 0-0.
  final int g1;
  final int g2;

  const MatchResult(this.outcome, [this.g1 = 0, this.g2 = 0]);

  Map<String, dynamic> toJson() => {'o': outcome.index, 'g1': g1, 'g2': g2};

  factory MatchResult.fromJson(Map<String, dynamic> j) =>
      MatchResult(Outcome.values[j['o'] as int], j['g1'] as int? ?? 0, j['g2'] as int? ?? 0);

  /// Text like "2-1" or "תיקו" from player 1's point of view.
  String scoreText({required int bestOf}) {
    switch (outcome) {
      case Outcome.doubleLoss:
        return 'הפסד כפול';
      case Outcome.draw:
        return bestOf > 1 ? '$g1-$g2 תיקו' : 'תיקו';
      case Outcome.p1:
      case Outcome.p2:
        return bestOf > 1 ? '$g1-$g2' : (outcome == Outcome.p1 ? '1-0' : '0-1');
    }
  }
}

class Match {
  final String id;
  int table;
  String p1;
  String? p2; // null = bye
  MatchResult? result;

  /// Top cut only: the match for 3rd place.
  final bool thirdPlace;

  Match({String? id, required this.table, required this.p1, this.p2, this.result, this.thirdPlace = false})
      : id = id ?? newId();

  bool get isBye => p2 == null;
  bool get done => isBye || result != null;

  String? get winner {
    if (isBye) return p1;
    switch (result?.outcome) {
      case Outcome.p1:
        return p1;
      case Outcome.p2:
        return p2;
      default:
        return null;
    }
  }

  String? get loser {
    if (isBye) return null;
    switch (result?.outcome) {
      case Outcome.p1:
        return p2;
      case Outcome.p2:
        return p1;
      default:
        return null;
    }
  }

  bool involves(String pid) => p1 == pid || p2 == pid;

  Map<String, dynamic> toJson() => {
        'id': id,
        'table': table,
        'p1': p1,
        'p2': p2,
        if (result != null) 'r': result!.toJson(),
        if (thirdPlace) 'third': true,
      };

  factory Match.fromJson(Map<String, dynamic> j) => Match(
        id: j['id'] as String,
        table: j['table'] as int,
        p1: j['p1'] as String,
        p2: j['p2'] as String?,
        result: j['r'] == null ? null : MatchResult.fromJson(j['r'] as Map<String, dynamic>),
        thirdPlace: j['third'] as bool? ?? false,
      );
}

class Round {
  final int number; // 1-based within its stage
  final Stage stage;
  final List<Match> matches;

  Round({required this.number, required this.stage, required this.matches});

  bool get complete => matches.every((m) => m.done);
  int get pending => matches.where((m) => !m.done).length;
  bool get anyResult => matches.any((m) => !m.isBye && m.result != null);

  Map<String, dynamic> toJson() =>
      {'n': number, 's': stage.index, 'm': matches.map((m) => m.toJson()).toList()};

  factory Round.fromJson(Map<String, dynamic> j) => Round(
        number: j['n'] as int,
        stage: Stage.values[j['s'] as int],
        matches: (j['m'] as List).map((e) => Match.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

/// Settings for the prize table.
class PrizeConfig {
  String unit; // ₪ or packs ("חבילות")
  double entryFee;
  double extra; // sponsor / store-added amount
  double houseCut; // percent kept by the organiser
  double step; // rounding step; 1 for packs
  bool splitTies; // average shares inside top-cut groups (3-4, 5-8, ...)
  List<double> percents; // per place, index 0 = 1st

  /// Default: prizes in booster packs, each player puts in one pack.
  PrizeConfig({
    this.unit = 'חבילות',
    this.entryFee = 1,
    this.extra = 0,
    this.houseCut = 0,
    this.step = 1,
    this.splitTies = true,
    List<double>? percents,
  }) : percents = percents ?? [50, 30, 20];

  Map<String, dynamic> toJson() => {
        'unit': unit,
        'fee': entryFee,
        'extra': extra,
        'cut': houseCut,
        'step': step,
        'split': splitTies,
        'pct': percents,
      };

  factory PrizeConfig.fromJson(Map<String, dynamic> j) => PrizeConfig(
        unit: j['unit'] as String? ?? '₪',
        entryFee: (j['fee'] as num?)?.toDouble() ?? 0,
        extra: (j['extra'] as num?)?.toDouble() ?? 0,
        houseCut: (j['cut'] as num?)?.toDouble() ?? 0,
        step: (j['step'] as num?)?.toDouble() ?? 1,
        splitTies: j['split'] as bool? ?? true,
        percents: (j['pct'] as List?)?.map((e) => (e as num).toDouble()).toList(),
      );
}

class Tournament {
  final String id;
  String name;
  final DateTime created;
  TFormat format;
  int swissRounds; // for round robin this is derived from the schedule
  int topCut; // 0 = none, otherwise 2/4/8/16/32/64
  int swissBestOf;
  int topBestOf;
  bool thirdPlace;
  double omwFloor; // e.g. 0.33; 0 to disable
  int roundMinutes;
  int overtimeMinutes; // counted down after the round clock hits zero
  final List<Player> players;
  final List<Round> rounds;
  bool finished;
  PrizeConfig prizes;

  /// Round robin: the full schedule, fixed when the event starts.
  List<List<List<String?>>>? rrSchedule;

  /// Round timer: when running, the wall-clock end. When paused, the
  /// remaining milliseconds.
  int? timerEndMs;
  int? timerPausedMs;

  Tournament({
    String? id,
    required this.name,
    DateTime? created,
    this.format = TFormat.swiss,
    this.swissRounds = 3,
    this.topCut = 0,
    this.swissBestOf = 3,
    this.topBestOf = 3,
    this.thirdPlace = false,
    this.omwFloor = 0.33,
    this.roundMinutes = 45,
    this.overtimeMinutes = 5,
    List<Player>? players,
    List<Round>? rounds,
    this.finished = false,
    PrizeConfig? prizes,
    this.rrSchedule,
    this.timerEndMs,
    this.timerPausedMs,
  })  : id = id ?? newId(),
        created = created ?? DateTime.now(),
        players = players ?? [],
        rounds = rounds ?? [],
        prizes = prizes ?? PrizeConfig();

  Player? player(String? id) {
    if (id == null) return null;
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  String nameOf(String? id) => id == null ? 'BYE' : (player(id)?.name ?? '?');

  List<Round> get swissRoundsList => rounds.where((r) => r.stage == Stage.swiss).toList();
  List<Round> get topRoundsList => rounds.where((r) => r.stage == Stage.top).toList();
  Round? get currentRound => rounds.isEmpty ? null : rounds.last;
  bool get started => rounds.isNotEmpty;
  List<Player> get activePlayers => players.where((p) => !p.dropped).toList();

  int get plannedSwissRounds => format == TFormat.roundRobin ? (rrSchedule?.length ?? rrRoundCount(players.length)) : swissRounds;

  bool get swissDone => swissRoundsList.length >= plannedSwissRounds && (swissRoundsList.isEmpty || swissRoundsList.last.complete);

  int bestOfFor(Stage s) => s == Stage.swiss ? swissBestOf : topBestOf;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created': created.millisecondsSinceEpoch,
        'format': format.index,
        'swissRounds': swissRounds,
        'topCut': topCut,
        'swissBo': swissBestOf,
        'topBo': topBestOf,
        'third': thirdPlace,
        'omwFloor': omwFloor,
        'minutes': roundMinutes,
        'ot': overtimeMinutes,
        'players': players.map((p) => p.toJson()).toList(),
        'rounds': rounds.map((r) => r.toJson()).toList(),
        'finished': finished,
        'prizes': prizes.toJson(),
        if (rrSchedule != null) 'rr': rrSchedule,
        if (timerEndMs != null) 'tEnd': timerEndMs,
        if (timerPausedMs != null) 'tPaused': timerPausedMs,
      };

  factory Tournament.fromJson(Map<String, dynamic> j) => Tournament(
        id: j['id'] as String,
        name: j['name'] as String,
        created: DateTime.fromMillisecondsSinceEpoch(j['created'] as int),
        format: TFormat.values[j['format'] as int? ?? 0],
        swissRounds: j['swissRounds'] as int? ?? 3,
        topCut: j['topCut'] as int? ?? 0,
        swissBestOf: j['swissBo'] as int? ?? 1,
        topBestOf: j['topBo'] as int? ?? 3,
        thirdPlace: j['third'] as bool? ?? false,
        omwFloor: (j['omwFloor'] as num?)?.toDouble() ?? 0.33,
        roundMinutes: j['minutes'] as int? ?? 45,
        overtimeMinutes: j['ot'] as int? ?? 5,
        players: (j['players'] as List).map((e) => Player.fromJson(e as Map<String, dynamic>)).toList(),
        rounds: (j['rounds'] as List).map((e) => Round.fromJson(e as Map<String, dynamic>)).toList(),
        finished: j['finished'] as bool? ?? false,
        prizes: j['prizes'] == null ? null : PrizeConfig.fromJson(j['prizes'] as Map<String, dynamic>),
        rrSchedule: (j['rr'] as List?)
            ?.map((r) => (r as List).map((p) => (p as List).map((x) => x as String?).toList()).toList())
            .toList(),
        timerEndMs: j['tEnd'] as int?,
        timerPausedMs: j['tPaused'] as int?,
      );
}

/// Rounds in a round robin for [n] players (odd counts get a bye each round).
int rrRoundCount(int n) => n < 2 ? 0 : (n.isOdd ? n : n - 1);

/// Recommended Swiss rounds by attendance (the common Bandai / TCG table).
int recommendedSwissRounds(int players) {
  if (players <= 2) return 1;
  if (players <= 8) return 3;
  if (players <= 16) return 4;
  if (players <= 32) return 5;
  if (players <= 64) return 6;
  if (players <= 128) return 7;
  if (players <= 226) return 8;
  if (players <= 409) return 9;
  return 10;
}

/// Recommended top cut by attendance.
int recommendedTopCut(int players) {
  if (players < 8) return 0;
  if (players <= 12) return 4;
  if (players <= 64) return 8;
  if (players <= 128) return 16;
  return 32;
}

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/models.dart';
import 'engine/pairing.dart';

/// App language. English by default; Hebrew is optional and also flips the
/// layout to right-to-left. Same pattern as Judgemon's l10n.dart.
class Lang extends ChangeNotifier {
  Lang._();
  static final instance = Lang._();
  static const key = 'zira.lang';

  String code = 'en';
  bool get he => code == 'he';
  TextDirection get direction => he ? TextDirection.rtl : TextDirection.ltr;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    code = p.getString(key) == 'he' ? 'he' : 'en';
    notifyListeners();
  }

  Future<void> toggle() async {
    code = he ? 'en' : 'he';
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(key, code);
  }
}

/// All UI strings. `S.t` follows [Lang.instance]. The engine stays
/// language-free; anything it returns as data is formatted here.
class S {
  static S get t => Lang.instance.he ? const S._he() : const S._en();

  final bool he;
  const S._en() : he = false;
  const S._he() : he = true;

  String _(String en, String heb) => he ? heb : en;

  // ---------------------------------------------------------------- app
  String get appName => _('Zira', 'זירה');
  String get langButton => _('עב', 'EN');
  String get langTooltip => _('עברית', 'English');
  String get tournaments => _('Tournaments', 'טורנירים');
  String get gameTools => _('Game tools', 'כלי משחק');

  // ---------------------------------------------------------------- common
  String get ok => _('OK', 'אישור');
  String get cancel => _('Cancel', 'ביטול');
  String get save => _('Save', 'שמירה');
  String copied(String what) => _('$what copied — ready to paste in WhatsApp', '$what הועתק — אפשר להדביק בוואטסאפ');
  String get vs => _('vs', 'נגד');
  String get dropped => _('Dropped', 'פרש');
  String get none => _('None', 'בלי');
  String top(int n) => _('Top $n', 'טופ $n');
  String round(int n) => _('Round $n', 'סיבוב $n');
  String roundOf(int n, int of) => _('Round $n/$of', 'סיבוב $n/$of');
  String roundOutOf(int n, int of) => _('Round $n of $of', 'סיבוב $n מתוך $of');
  String players(int n) => _(n == 1 ? '1 player' : '$n players', '$n שחקנים');
  String pts(int n) => _('$n pts', '$n נק׳');
  String get swiss => _('Swiss', 'סוויס');
  String get roundRobin => _('Round robin', 'ראונד רובין');
  String get topCut => _('Top cut', 'טופ קאט');
  String get topCutOption => _('Top cut', 'טופ קאט');
  String get settings => _('Settings', 'הגדרות');
  String get tournamentName => _('Tournament name', 'שם הטורניר');
  String get playerName => _('Player name', 'שם השחקן');

  /// Bracket round by how many players are in it.
  String topRoundName(int players) => switch (players) {
        2 => _('Final', 'גמר'),
        4 => _('Semifinals', 'חצי גמר'),
        8 => _('Quarterfinals', 'רבע גמר'),
        _ => top(players),
      };

  /// Round label for chips, headers and copied text.
  String roundLabel(Round r) => r.stage == Stage.swiss ? round(r.number) : topRoundName(topRoundSize(r));

  /// "2-1", "Draw" etc. from player 1's point of view.
  String scoreText(MatchResult r, {required int bestOf}) {
    switch (r.outcome) {
      case Outcome.doubleLoss:
        return doubleLoss;
      case Outcome.draw:
        return bestOf > 1 ? '${r.g1}-${r.g2} ${draw.toLowerCase()}' : draw;
      case Outcome.p1:
      case Outcome.p2:
        return bestOf > 1 ? '${r.g1}-${r.g2}' : (r.outcome == Outcome.p1 ? '1-0' : '0-1');
    }
  }

  String get draw => _('Draw', 'תיקו');
  String get doubleLoss => _('Double loss', 'הפסד כפול');
  String get doubleLossShort => _('Double\nloss', 'הפסד\nכפול');

  // ---------------------------------------------------------------- tournaments list
  String get copyBackup => _('Copy a backup of all tournaments', 'העתקת גיבוי של כל הטורנירים');
  String get restoreBackup => _('Restore a backup from the clipboard', 'שחזור גיבוי מהלוח');
  String get newTournament => _('New tournament', 'טורניר חדש');
  String get noTournaments => _('No tournaments yet', 'עוד אין טורנירים');
  String get noTournamentsBody => _('Open a tournament, add players, and the app pairs, ranks and works out the prizes.',
      'פתחו טורניר, הוסיפו שחקנים, והאפליקציה תזווג, תדרג ותחשב פרסים.');
  String get backupWhat => _('Backup', 'הגיבוי');
  String restored(int n) => _(n == 1 ? 'Restored 1 tournament' : 'Restored $n tournaments', 'שוחזרו $n טורנירים');
  String get badBackup => _('The clipboard has no valid backup. Copy a backup from the app first.',
      'בלוח אין גיבוי תקין. העתיקו קודם גיבוי מהאפליקציה.');
  String deleteTitle(String name) => _('Delete "$name"?', 'למחוק את "$name"?');
  String get deleteBody => _('All rounds and results will be deleted. This cannot be undone.',
      'כל הסיבובים והתוצאות יימחקו. אי אפשר לבטל.');
  String get delete => _('Delete', 'מחיקה');
  String get statusFinished => _('Finished', 'הסתיים');
  String get statusRegistration => _('Registration', 'הרשמה');

  // ---------------------------------------------------------------- create
  String defaultTournamentName(int day, int month) => _('Tournament $day.$month', 'טורניר $day.$month');
  String get format => _('Format', 'שיטה');
  String get rrExplain => _('Everyone plays everyone else once. Good for small groups (up to ~10).',
      'כל שחקן משחק נגד כל השאר פעם אחת. מתאים לקבוצות קטנות (עד ~10).');
  String get swissExplain => _('Each round you play someone on the same points, never the same opponent twice. The Bandai event system.',
      'בכל סיבוב משחקים מול שחקנים עם אותו ניקוד, בלי משחק חוזר. השיטה של טורנירי Bandai.');
  String get playersTitle => _('Players', 'שחקנים');
  String get playersHint => _('One name per line (you can paste a list)\nPlayers can also be added later',
      'שם בכל שורה (אפשר להדביק רשימה)\nאפשר להוסיף שחקנים גם אחר כך');
  String get swissRounds => _('Swiss rounds', 'סיבובי סוויס');
  String recommendedFor(int n, int r) => _('Recommended for $n players: $r', 'מומלץ ל-$n שחקנים: $r');
  String get rounds => _('Rounds', 'סיבובים');
  String get setByPlayers => _('Set by the number of players', 'נקבע לפי מספר השחקנים');
  String topCutUsual(int n, int top) => _('Knockout between the leaders. Usual for $n players: Top $top',
      'נוקאאוט בין המובילים. מקובל ל-$n שחקנים: טופ $top');
  String get topCutExplain => _('Knockout between the leaders after the rounds', 'נוקאאוט בין המובילים אחרי הסיבובים');
  String get gamesPerRound => _('Games per match', 'משחקים בסיבוב');
  String get gamesPerTop => _('Games per top-cut match', 'משחקים בטופ קאט');
  String get thirdPlaceMatch => _('3rd-place match', 'משחק על המקום השלישי');
  String get roundTime => _('Round time', 'זמן סיבוב');
  String get overtime => _('Overtime', 'תוספת זמן (overtime)');
  String get overtimeExplain => _('Counted after the round time runs out', 'נספרת אחרי שזמן הסיבוב נגמר');
  String get createNoPlayers => _('Create (players can be added later)', 'יצירה (שחקנים אפשר להוסיף אחר כך)');
  String createWith(int n) => _('Create tournament with $n players', 'יצירת טורניר עם $n שחקנים');

  // ---------------------------------------------------------------- tournament screen
  String active(int n) => _('$n active', '$n פעילים');
  String get tabPlayers => _('Players', 'שחקנים');
  String get tabRounds => _('Rounds', 'סיבובים');
  String get tabStandings => _('Standings', 'דירוג');
  String get tabBracket => _('Top cut', 'טופ קאט');
  String get tabPrizes => _('Prizes', 'פרסים');
  String get tournamentOver => _('Tournament finished', 'הטורניר הסתיים');
  String champion(String name) => _('Champion: $name', 'אלוף: $name');
  String get needTwoPlayers => _('At least 2 players needed', 'צריך לפחות 2 שחקנים');
  String get startTournament => _('Start the tournament · Round 1', 'התחלת הטורניר · סיבוב 1');
  String missingResults(int n) => n == 1 ? _('1 result missing', 'חסרה תוצאה אחת') : _('$n results missing', 'חסרות $n תוצאות');
  String pairRound(int n) => _('Pair round $n', 'זיווג סיבוב $n');
  String startTop(int n) => _('Start top $n', 'התחלת טופ $n');
  String create(String what) => _('Create $what', 'יצירת $what');
  String get finishTournament => _('Finish the tournament · final standings', 'סיום הטורניר ודירוג סופי');

  // ---------------------------------------------------------------- settings sheet
  String get tournamentSettings => _('Tournament settings', 'הגדרות טורניר');
  String get name => _('Name', 'שם');
  String recommendedPlayed(int r, int played) =>
      _('Recommended: $r${played > 0 ? ' · $played played' : ''}', 'מומלץ: $r${played > 0 ? ' · שוחקו $played' : ''}');
  String get rrRoundsBySchedule => _('The number of rounds is set by the players', 'מספר הסיבובים נקבע לפי השחקנים');
  String get topAlreadyStarted => _('The top cut has already started', 'הטופ כבר התחיל');
  String get tournamentFinishedLocked => _('The tournament has finished', 'הטורניר הסתיים');
  String get omwFloor => _('OMW% floor', 'רצפה ל-OMW%');
  String get omwFloorExplain => _(
      'The lowest win rate counted for a weak opponent when working out the tiebreaker. Default 33%.',
      'אחוז הנצחונות המינימלי שנספר ליריב חלש בחישוב שובר השוויון. ברירת מחדל 33%.');
  String get tiebreakExplain => _(
      'Tiebreakers in order: points → OMW% (opponents\' average win rate) → OOMW% (opponents\' average OMW) → random draw. Win 3, draw (including 0-0) 1, loss 0, a BYE counts as a win.',
      'שוברי שוויון לפי סדר: נקודות ← OMW% (ממוצע אחוזי הנצחון של היריבים) ← OOMW% (ממוצע ה-OMW של היריבים) ← הגרלה. נצחון 3, תיקו (כולל 0-0) 1, הפסד 0, BYE נחשב נצחון.');

  // ---------------------------------------------------------------- rounds tab
  String get notStarted => _('The tournament hasn\'t started yet', 'הטורניר עוד לא התחיל');
  String get notStartedBody => _(
      'When all the players are registered, tap "Start the tournament" below and the round 1 pairings appear here.',
      'כשכל השחקנים רשומים, לחצו על "התחלת הטורניר" למטה והזיווג של סיבוב 1 יופיע כאן.');
  String get complete => _('Complete', 'הושלם');
  String openMatches(int n) => _('$n open', '$n פתוחים');
  String get copyPairings => _('Copy pairings', 'העתקת זיווגים');
  String get pairingsWhat => _('Pairings', 'הזיווג');
  String get repaired => _('Round paired again', 'הסיבוב זווג מחדש');
  String undoTitle(String round) => _('Undo $round?', 'לבטל את $round?');
  String get undoBody => _('The pairings will be deleted and you can create them again.', 'הזיווג יימחק ותוכלו ליצור אותו שוב.');
  String get repair => _('Pair again', 'זיווג מחדש');
  String get undoRound => _('Undo the round', 'ביטול הסיבוב');
  String get dropTitle => _('Drop before the next round', 'פרישה לפני הסיבוב הבא');
  String get dropBody => _('The player finishes the current round (the result is kept) and won\'t be paired again.',
      'השחקן מסיים את הסיבוב הנוכחי (התוצאה נשמרת) ולא יזווג יותר.');
  String get droppedNotPaired => _('Dropped — won\'t be paired next round', 'פרש — לא יזווג בסיבוב הבא');
  String get stillPlaying => _('Still in the tournament', 'ממשיך בטורניר');
  String get thirdPlaceTag => _('3rd place', 'מקום 3');
  String table(int n) => _('Table $n', 'שולחן $n');
  String get autoWin => _('Automatic win', 'נצחון אוטומטי');
  String get drop => _('Drop', 'פרישה');

  // ---------------------------------------------------------------- players tab
  String get lateEntry => _('Late entry — joins from the next round on 0 points', 'נוסף באיחור — ישתתף מהסיבוב הבא עם 0 נקודות');
  String get add => _('Add', 'הוספה');
  String get noPlayers => _('No players yet', 'אין עדיין שחקנים');
  String get noPlayersBody => _('Type a name and tap Add. You can also paste a list, one name per line.',
      'הקלידו שם ולחצו הוספה. אפשר גם להדביק רשימה, שם בכל שורה.');
  String get rename => _('Rename', 'שינוי שם');
  String get undrop => _('Back into the tournament', 'החזרה לטורניר');
  String get dropFromTournament => _('Drop from the tournament', 'פרישה מהטורניר');
  String get remove => _('Remove', 'הסרה');
  String dropPlayerTitle(String name) => _('Drop $name', 'פרישה של $name');
  String get dropPlayerBody => _(
      'The player won\'t be paired in later rounds. Results already reported stay and count towards the opponents\' tiebreakers.',
      'השחקן לא יזווג בסיבובים הבאים. התוצאות שכבר נרשמו נשארות ונספרות לשוברי השוויון של היריבים.');

  // ---------------------------------------------------------------- standings
  String get noStandings => _('No standings yet', 'אין דירוג עדיין');
  String get noStandingsBody => _('Add players and start a round.', 'הוסיפו שחקנים והתחילו סיבוב.');
  String get beforeRound1 => _('Before round 1', 'לפני סיבוב 1');
  String afterRounds(int n, bool last) =>
      _('After ${n == 1 ? '1 round' : '$n rounds'}${last ? ' (final)' : ''}', 'אחרי $n סיבובים${last ? ' (סופי)' : ''}');
  String get copyStandings => _('Copy standings', 'העתקת דירוג');
  String get standingsWhat => _('Standings', 'הדירוג');
  String cutMarked(int n) =>
      _('Marked in yellow: would make the top $n if the event ended now', 'מסומנים בצהוב: עולים לטופ $n אם הטורניר היה נגמר עכשיו');
  String get colPlayer => _('Player', 'שחקן');
  String get colPts => _('Pts', 'נק׳');
  String get colRecord => _('W-L', 'מאזן');
  String get standingsLegend => _('Order: points → OMW% → OOMW% → fixed random draw. Win 3 · draw 1 · loss 0 · BYE = win.',
      'סדר הדירוג: נקודות ← OMW% ← OOMW% ← הגרלה קבועה. נצחון 3 · תיקו 1 · הפסד 0 · BYE = נצחון.');
  String standingsHeader(String name) => _('$name — standings', '$name — דירוג');
  String get droppedTag => _('[dropped]', '[פרש]');

  // ---------------------------------------------------------------- bracket
  String get noTopCut => _('No top cut', 'אין טופ קאט');
  String get noTopCutBody => _('You can turn on a top cut in the settings (the sliders icon at the top).',
      'אפשר להפעיל טופ קאט בהגדרות (סמל המחוונים למעלה).');
  String get tournamentChampion => _('Tournament champion', 'אלוף הטורניר');
  String get bracketPreview => _('Preview from the current standings. The pairings are set when you start the top cut.',
      'תצוגה מקדימה לפי הדירוג הנוכחי. הזיווג ייקבע כשתתחילו את הטופ קאט.');

  // ---------------------------------------------------------------- prizes
  String get prizePool => _('Prize pool', 'קופת הפרסים');
  String get money => _('Money ₪', 'כסף ₪');
  String get packsOption => _('Packs', 'חבילות');
  String get entryFee => _('Entry fee', 'דמי השתתפות');
  String get packsPerPlayer => _('Packs per player', 'חבילות לשחקן');
  String get addedToPool => _('Added to the pool', 'תוספת לקופה');
  String get playerCount => _('Number of players', 'מספר שחקנים');
  String get organiserCut => _('Organiser\'s cut', 'עמלת מארגן');
  String organiserKeeps(String amount) => _('The organiser keeps $amount', 'נשאר למארגן $amount');
  String get rounding => _('Round amounts', 'עיגול סכומים');
  String roundTo(String amount) => _('To $amount', 'לכל $amount');
  String get splitTies => _('Equal split in the top cut', 'חלוקה שווה בטופ קאט');
  String get splitTiesExplain => _('Players knocked out at the same stage (3-4, 5-8) get the same amount',
      'מי שהודחו באותו שלב (3-4, 5-8) מקבלים אותו סכום');
  String poolFormula(int players, String fee) => _('$players players × $fee', '$players שחקנים × $fee');
  String get toHandOut => _('to hand out', 'לחלוקה');
  String get split => _('Split', 'חלוקה');
  String total(String v) => _('Total $v', 'סה״כ $v');
  String get presetWinnerTakesAll => _('Winner takes all', 'מנצח לוקח הכל');
  String presetEven(int n) => _('Even ×$n', 'שווה ×$n');
  String presetStepped(int n) => _('Stepped ×$n', 'מדורג ×$n');
  String get over100 => _('The percentages add up to more than 100% — the amounts exceed the pool.',
      'האחוזים עוברים את 100% — הסכומים גדולים מהקופה.');
  String leftUnsplit(String pct) => _('$pct% left unassigned.', 'נשארו $pct% שלא מחולקים.');
  String get balance => _('Balance to 100%', 'איזון ל-100%');
  String get colPlace => _('Place', 'מקום');
  String get colPercent => _('%', 'אחוז');
  String get colAmount => _('Amount', 'סכום');
  String get place => _('Place', 'מקום');
  String notHandedOut(String amount) => _('Not handed out: $amount', 'לא חולק: $amount');
  String get standaloneNote => _('Standalone calculator. Inside a tournament the table fills in names from the final standings.',
      'מחשבון עצמאי. בתוך טורניר הטבלה מתמלאת בשמות לפי הדירוג הסופי.');
  String get finalNote => _('Standings are final. The names in the table are the winners.', 'הדירוג סופי. השמות בטבלה הם הזוכים.');
  String get liveNote => _('Names follow the current standings and update until the event ends.',
      'השמות לפי המצב הנוכחי ויתעדכנו עד סוף הטורניר.');
  String get copyPrizes => _('Copy the prize table', 'העתקת טבלת הפרסים');
  String get prizesWhat => _('Prize table', 'טבלת הפרסים');
  String get prizeSplitHeader => _('Prize split', 'חלוקת פרסים');
  String prizesHeader(String name) => _('$name — prizes', '$name — פרסים');
  String poolLine(String amount) => _('Pool to hand out: $amount', 'קופה לחלוקה: $amount');

  /// Amount in the prize unit: "₪120" or "12 packs".
  String amount(String unit, double v) {
    final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    if (unit == PrizeConfig.ils) return '₪$s';
    return _(v == 1 ? '$s pack' : '$s packs', '$s חבילות');
  }

  // ---------------------------------------------------------------- result sheet
  String won(String name) => _('$name won', '$name ניצח');
  String drawScore(String score) => _('Draw $score', 'תיקו $score');
  String get drawNote => _('Draw = a point each. 0-0 when time ran out and no game was decided.',
      'תיקו = נקודה לכל שחקן. 0-0 כשנגמר הזמן ואף משחק לא הוכרע.');
  String get topTimeoutRule => _(
      'Top cut: when time runs out — turn 0 plus one more turn (if on the first player\'s turn) or two (if on the second player\'s). Then decide by: more security cards → more cards in deck → more Digimon in play → more cards in hand → random.',
      'טופ קאט: כשהזמן נגמר — תור 0 ועוד תור (אם בתור הראשון) או שניים (אם בתור השני). אחר כך מכריעים לפי: יותר קלפי סקיוריטי ← יותר קלפים בחפיסה ← יותר דיג׳ימונים בשטח ← יותר קלפים ביד ← הגרלה.');
  String get clearResult => _('Clear the result', 'מחיקת התוצאה');

  // ---------------------------------------------------------------- timer
  String get timeLeft => _('Time left', 'זמן שנותר');
  String roundClock(int minutes, int ot) => _('Round clock · $minutes′ + $ot′', 'שעון סיבוב · $minutes′ + $ot′');
  String get overtimeLabel => _('Overtime', 'תוספת זמן (overtime)');
  String get timeUp => _('Time\'s up', 'הזמן נגמר');
  String get fullScreen => _('Full screen', 'מסך מלא');
  String get addMinute => _('One more minute', 'דקה נוספת');
  String get reset => _('Reset', 'איפוס');
  String get tapToPause => _('Tap to pause', 'הקישו כדי לעצור');
  String get tapToStart => _('Tap to start', 'הקישו כדי להפעיל');
  String overtimeCaption(int n) => _('OVERTIME — $n extra minutes', 'OVERTIME — $n דקות תוספת');
  String get timeUpCaption => _('Time\'s up — finish the current action', 'הזמן נגמר — מסיימים את הפעולה הנוכחית');

  // ---------------------------------------------------------------- tools
  String get memoryGauge => _('Memory gauge', 'מד זיכרון');
  String get memoryGaugeBody => _('Digimon memory gauge: passes the turn by itself when memory crosses to the opponent\'s side.',
      'Memory gauge לדיג׳ימון: מעביר תור לבד כשהזיכרון עובר לצד של היריב.');
  String get dice => _('Dice', 'קוביות');
  String get diceBody => _('Includes "who goes first"', 'כולל "מי מתחיל"');
  String get coin => _('Coin', 'מטבע');
  String get coinBody => _('Heads or tails', 'עץ או פלי');
  String get rps => _('Rock paper scissors', 'אבן נייר ומספריים');
  String get rpsBody => _('Two players or against the phone', 'שני שחקנים או נגד הטלפון');
  String get prizeCalculator => _('Prize calculator', 'מחשבון פרסים');
  String get prizeCalculatorBody => _('Without a tournament', 'בלי טורניר');
  String get digimonRules => _('Digimon rules', 'חוקי דיג׳ימון');
  String get digimonRulesBody => _('Rule manual, Comprehensive Rules, glossary and the banned card list.',
      'חוברת החוקים, Comprehensive Rules, מילון מונחים ורשימת הקלפים האסורים.');

  // dice
  String get tieRollAgain => _('Tie — roll again', 'שוויון — מטילים שוב');
  String get blueFirst => _('Blue goes first', 'שחקן כחול מתחיל');
  String get orangeFirst => _('Orange goes first', 'שחקן כתום מתחיל');
  String get whoFirst => _('Who goes first?', 'מי מתחיל?');
  String get freeRoll => _('Free roll', 'הטלה חופשית');
  String get howMany => _('How many:', 'כמה:');
  String get roll => _('Roll', 'הטלה');
  String get tapToRoll => _('Tap anywhere to roll', 'הקישו בכל מקום להטלה');
  String get blue => _('Blue', 'כחול');
  String get orange => _('Orange', 'כתום');
  String get firstRollHelp => _('Each player rolls a die. The higher one goes first.', 'כל שחקן מקבל קובייה. הגבוהה מתחילה.');

  // coin
  String get heads => _('Heads', 'עץ');
  String get tails => _('Tails', 'פלי');
  String get headsLetter => _('H', 'ע');
  String get tailsLetter => _('T', 'פ');
  String coinTally(int h, int t, int n) => _('Heads $h · tails $t  (last $n)', 'עץ $h · פלי $t  ($n אחרונות)');
  String get flip => _('Flip the coin', 'הטלת מטבע');

  // rock paper scissors
  List<String> get hands => he ? const ['אבן', 'נייר', 'מספריים'] : const ['Rock', 'Paper', 'Scissors'];
  List<String> get countdown => he ? const ['אבן...', 'נייר...', 'מספריים!'] : const ['Rock...', 'Paper...', 'Scissors!'];
  String get you => _('You', 'אתם');
  String get phone => _('Phone', 'הטלפון');
  String get resetScore => _('Reset score', 'איפוס ניקוד');
  String get twoPlayers => _('Two players', 'שני שחקנים');
  String get vsPhone => _('Against the phone', 'נגד הטלפון');
  String draws(int n) => _('Draws $n', 'תיקו $n');
  String get pickHand => _('Pick a hand', 'בחרו יד');
  String pickSecret(String who) => _('$who\'s turn to pick — don\'t let the other player see', 'תור $who לבחור — בלי שהשני יראה');
  String passPhone(String a, String b) => _('$a has picked. Pass the phone to $b.', '$a בחר. מעבירים את הטלפון ל$b.');
  String iAm(String b) => _('I\'m $b — continue', 'אני $b — להמשיך');
  String get drawBang => _('Draw!', 'תיקו!');
  String get youWin => _('You win!', 'ניצחתם!');
  String wins(String who) => _('$who wins!', '$who ניצח!');
  String get playAgain => _('Play again', 'עוד סיבוב');

  // memory gauge
  String get bluePlayer => _('Blue player', 'שחקן כחול');
  String get orangePlayer => _('Orange player', 'שחקן כתום');
  static const defaultNames = {'Blue player', 'שחקן כחול', 'Orange player', 'שחקן כתום'};
  String turnOf(String name) => _('$name\'s turn', 'התור של $name');
  String goesFirst(String name) => _('$name goes first', '$name מתחיל');
  String get newGameRoll => _('New game — roll for who goes first', 'משחק חדש — הגרלה מי מתחיל');
  String newGameFirst(String name) => _('New game — $name goes first', 'משחק חדש — $name מתחיל');
  String get passManually => _('Pass the turn by hand', 'העברת התור ידנית');
  String get resetWins => _('Reset wins', 'איפוס ניצחונות');
  String rolled(int a, int b, String name) => _('🎲 $a vs $b — $name goes first', '🎲 $a מול $b — $name מתחיל');
  String gameWonTitle(String name) => _('Did $name win the game?', '$name ניצח במשחק?');
  String get gameWonBody => _('A win is added and a new game starts. The loser goes first next game.',
      'יתווסף ניצחון ויתחיל משחק חדש. המפסיד מתחיל במשחק הבא.');
  String get yesNewGame => _('Yes, new game', 'כן, משחק חדש');
  String get exit => _('Exit', 'יציאה');
  String get undo => _('Undo', 'ביטול פעולה');
  String get newGame => _('New game', 'משחק חדש');
  String turnNumber(int n) => _('Turn $n', 'תור $n');
  String get yourTurn => _('Your turn', 'התור שלך');
  String get waiting => _('Waiting', 'ממתין');
  String get longPressWin => _('Long press: game won', 'לחיצה ארוכה: ניצחון במשחק');
  String get memory => _('Memory', 'זיכרון');
  String get endTurn => _('End turn', 'סיום תור');

  // rules links
  String get cantOpenLink => _('Couldn\'t open the link', 'לא הצלחנו לפתוח את הקישור');
  String get rulesFooter => _('The documents are in English, from Bandai\'s official site. The links always open the current version.',
      'המסמכים באנגלית, מהאתר הרשמי של Bandai. הקישורים פותחים תמיד את הגרסה העדכנית.');
  String get ruleManual => _('Rule Manual', 'Rule Manual — חוברת החוקים');
  String get ruleManualBody => _('The basic rules in plain language, with examples. Good for beginners.',
      'החוקים הבסיסיים בצורה פשוטה, עם דוגמאות. מתאים למתחילים.');
  String get comprehensive => 'Comprehensive Rules';
  String get comprehensiveBody => _('The full, exact rules for every situation — for judges and disputes.',
      'החוקים המלאים והמדויקים לכל מצב — לשופטים ולמחלוקות.');
  String get glossary => _('Glossary', 'Glossary — מילון מונחים');
  String get glossaryBody => _('Terms and keyword effects explained.', 'הסבר על מונחים ומילות מפתח של אפקטים (Keyword effects).');
  String get banned => _('Banned & restricted cards', 'קלפים אסורים ומוגבלים');
  String get bannedBody => _('The current Banned / Restricted list.', 'רשימת ה-Banned / Restricted העדכנית.');
  String get ruleChanges => _('Rule changes', 'שינויי חוקים');
  String get ruleChangesBody => _('Official announcements of rulings and rule changes.', 'הודעות רשמיות על שינויי פסיקה וחוקים.');
  String get floorRules => 'Floor Rules';
  String get floorRulesBody => _('Conduct and procedures at official events.', 'כללי התנהגות ונהלים בטורנירים רשמיים.');
  String get allRules => _('The full official rules page', 'כל עמוד החוקים הרשמי');
  String get allRulesBody => _('Including Q&A and more documents.', 'כולל Q&A ומסמכים נוספים.');

  // ---------------------------------------------------------------- account
  String get signIn => _('Sign in', 'התחברות');
  String get signInGoogle => _('Continue with Google', 'המשך עם Google');
  String get email => _('Email', 'אימייל');
  String get password => _('Password', 'סיסמה');
  String get displayNameLabel => _('Your name', 'השם שלך');
  String get register => _('Create account', 'יצירת חשבון');
  String get haveAccount => _('I have an account', 'יש לי חשבון');
  String get noAccount => _('New here? Create an account', 'חדש כאן? יצירת חשבון');
  String get forgotPassword => _('Forgot password?', 'שכחתי סיסמה');
  String get resetSent => _('Reset link sent — check your email', 'נשלח קישור לאיפוס — בדוק את האימייל');
  String get signInNeeded => _('Sign in to run and join tournaments', 'התחבר כדי לנהל טורנירים ולהצטרף אליהם');
  String get account => _('Account', 'חשבון');
  String get signOut => _('Sign out', 'התנתקות');
  String get deleteAccount => _('Delete account', 'מחיקת חשבון');
  String get deleteAccountBody => _('Your account is deleted. Your name stays in past tournaments.',
      'החשבון יימחק. השם שלך יישאר בטורנירים שהיו.');
  String get signInAgain => _('Please sign in again, then delete.', 'צריך להתחבר שוב ואז למחוק.');
  String authError(String code) => switch (code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' => _('Wrong email or password', 'אימייל או סיסמה שגויים'),
        'email-already-in-use' => _('This email already has an account', 'לאימייל הזה כבר יש חשבון'),
        'weak-password' => _('Password must be at least 6 characters', 'סיסמה של 6 תווים לפחות'),
        'invalid-email' => _('Invalid email', 'אימייל לא תקין'),
        'network-request-failed' => _('No connection', 'אין חיבור'),
        _ => _('Sign-in failed ($code)', 'ההתחברות נכשלה ($code)'),
      };
  String migrated(int n) => _('$n tournaments moved to your account', '$n טורנירים הועברו לחשבון שלך');
}

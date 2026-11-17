import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/memory.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/round_timer.dart' show KeepAwake;

/// Digimon Card Game memory gauge. The phone lies sideways between the two
/// players, like a real gauge card: big circles along the middle, and each
/// player's small controls along their own long edge, turned to face them.
/// Tap any circle to move the marker there. The turn only changes when the
/// turn player taps End turn: the app can't know whether it really passed.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  static const _prefsKey = 'zira.memory.v1';

  MemoryState _m = const MemoryState();
  final List<MemoryState> _undo = [];
  // Null = the default name, shown in the current language.
  String? _bottomCustom;
  String? _topCustom;
  String get _bottomName => _bottomCustom ?? S.t.bluePlayer;
  String get _topName => _topCustom ?? S.t.orangePlayer;
  int _bottomWins = 0, _topWins = 0;

  String? _banner;
  Side _bannerSide = Side.bottom;
  Timer? _bannerTimer;

  /// The player whose "Pay" number pad is open.
  Side? _paying;

  @override
  void initState() {
    super.initState();
    KeepAwake.acquire();
    // Status bar hidden for more room; the navigation bar (back) stays.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [SystemUiOverlay.bottom]);
    // The phone lies sideways between the players: always landscape.
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _load();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    KeepAwake.release();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_prefsKey);
    if (raw == null || !mounted) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _m = MemoryState.fromJson(j['m'] as Map<String, dynamic>);
        _bottomCustom = _custom(j['bn']);
        _topCustom = _custom(j['tn']);
        _bottomWins = j['bw'] as int? ?? 0;
        _topWins = j['tw'] as int? ?? 0;
      });
    } catch (_) {}
  }

  /// Older saves stored the Hebrew default names; treat any default as unset.
  static String? _custom(Object? v) => v is String && v.isNotEmpty && !S.defaultNames.contains(v) ? v : null;

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _prefsKey,
      jsonEncode({'m': _m.toJson(), 'bn': _bottomCustom, 'tn': _topCustom, 'bw': _bottomWins, 'tw': _topWins}),
    );
  }

  String _name(Side s) => s == Side.bottom ? _bottomName : _topName;
  Color _color(Side s) => s == Side.bottom ? Z.blue : Z.coral;

  void _apply(MemoryState next) {
    if (next.value == _m.value && next.turn == _m.turn && next.turnNumber == _m.turnNumber) return;
    final passed = next.turn != _m.turn;
    _undo.add(_m);
    if (_undo.length > 200) _undo.removeAt(0);
    setState(() {
      _m = next;
      _paying = null;
    });
    if (passed) {
      HapticFeedback.heavyImpact();
      _showBanner(S.t.turnOf(_name(next.turn)), next.turn);
    } else {
      HapticFeedback.selectionClick();
    }
    _save();
  }

  void _showBanner(String text, Side side) {
    _bannerTimer?.cancel();
    setState(() {
      _banner = text;
      _bannerSide = side;
    });
    _bannerTimer = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  void _doUndo() {
    if (_undo.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _m = _undo.removeLast());
    _save();
  }

  void _newGame({Side? first}) {
    setState(() {
      _undo.clear();
      _m = MemoryState(turn: first ?? Side.bottom);
    });
    _showBanner(S.t.goesFirst(_name(_m.turn)), _m.turn);
    _save();
  }

  Future<void> _menu() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.casino),
              title: Text(S.t.newGameRoll),
              onTap: () => Navigator.pop(c, 'roll'),
            ),
            ListTile(
              leading: const Icon(Icons.south, color: Z.blue),
              title: Text(S.t.newGameFirst(_bottomName)),
              onTap: () => Navigator.pop(c, 'bottom'),
            ),
            ListTile(
              leading: const Icon(Icons.north, color: Z.coral),
              title: Text(S.t.newGameFirst(_topName)),
              onTap: () => Navigator.pop(c, 'top'),
            ),
            ListTile(
              leading: const Icon(Icons.exposure_zero),
              title: Text(S.t.resetWins),
              onTap: () => Navigator.pop(c, 'wins'),
            ),
          ],
        ),
      ),
    );
    switch (v) {
      case 'roll':
        _rollFirst();
      case 'bottom':
        _newGame(first: Side.bottom);
      case 'top':
        _newGame(first: Side.top);
      case 'wins':
        setState(() => _bottomWins = _topWins = 0);
        _save();
    }
  }

  void _rollFirst() {
    final r = Random.secure();
    int a, b;
    do {
      a = r.nextInt(6) + 1;
      b = r.nextInt(6) + 1;
    } while (a == b);
    _newGame(first: a > b ? Side.bottom : Side.top);
    _showBanner(S.t.rolled(a, b, _name(_m.turn)), _m.turn);
  }

  Future<void> _rename(Side s) async {
    final v = await promptText(context, S.t.playerName, initial: _name(s));
    if (v == null || v.isEmpty) return;
    setState(() => s == Side.bottom ? _bottomCustom = _custom(v) : _topCustom = _custom(v));
    _save();
  }

  /// Records a game win. Who starts the next game is asked, never assumed.
  Future<void> _gameWon(Side s) async {
    final first = await showDialog<Side>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(S.t.gameWonTitle(_name(s)), style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(S.t.gameWonBody, style: const TextStyle(height: 1.45)),
            const SizedBox(height: 14),
            for (final side in [s.other, s])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton(
                  key: ValueKey('first-${side.name}'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _color(side),
                    foregroundColor: Z.ink,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => Navigator.pop(c, side),
                  child: Text(
                    _name(side),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(S.t.cancel))],
      ),
    );
    if (first == null || !mounted) return;
    setState(() => s == Side.bottom ? _bottomWins++ : _topWins++);
    _newGame(first: first);
  }

  void _pay(Side s, int n) {
    setState(() => _paying = null);
    _apply(_m.adjust(s, -n));
  }

  /// The phone lies sideways between the two players, like a real gauge card:
  /// the gauge runs along the long axis in the middle, and each player has a
  /// slim strip of controls along their own long edge, facing them.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Z.ink,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final table = _table();
            // Where the screen can't be turned (a browser held upright), turn the layout instead.
            return box.maxHeight > box.maxWidth ? RotatedBox(quarterTurns: 1, child: table) : table;
          },
        ),
      ),
    );
  }

  Widget _table() {
    return Stack(
      children: [
        Column(
          children: [
            RotatedBox(quarterTurns: 2, child: _panel(Side.top)),
            RotatedBox(quarterTurns: 2, child: _turnRow(Side.top)),
            Expanded(
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _gauge()),
            ),
            _turnRow(Side.bottom),
            _panel(Side.bottom),
          ],
        ),
        if (_banner != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: RotatedBox(
                  quarterTurns: _bannerSide == Side.top ? 2 : 0,
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(_banner),
                    tween: Tween(begin: .7, end: 1),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutBack,
                    builder: (_, s, c) => Transform.scale(scale: s, child: c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                      decoration: BoxDecoration(
                        color: _color(_bannerSide),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: _color(_bannerSide).withValues(alpha: .5), blurRadius: 30)],
                      ),
                      child: Text(
                        _banner!,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Z.ink),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The thin line between a player's strip and the gauge: the turn number,
  /// and on the bottom player's side also exit / undo / new game.
  Widget _turnRow(Side s) {
    Widget b(IconData i, String tip, VoidCallback? on) => IconButton(
      tooltip: tip,
      onPressed: on,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 30),
      icon: Icon(i, size: 21),
      color: Z.muted,
    );
    return SizedBox(
      height: 30,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            if (s == Side.bottom) ...[
              b(Icons.close, S.t.exit, () => Navigator.pop(context)),
              b(Icons.undo, S.t.undo, _undo.isEmpty ? null : _doUndo),
              b(Icons.casino_outlined, S.t.newGame, _menu),
            ],
            const Spacer(),
            Text(
              S.t.turnNumber(_m.turnNumber),
              style: const TextStyle(
                fontSize: 12.5,
                color: Z.muted,
                fontWeight: FontWeight.w700,
                fontFeatures: Z.tabular,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The gauge, 10 … 0 … 10 along the phone. The circles zigzag over two
  /// rows so each can be far larger than a single row of 21 would allow.
  Widget _gauge() {
    return LayoutBuilder(
      builder: (context, box) {
        final pitch = box.maxWidth / 21.6; // 20 steps + one circle of 1.6 steps
        var d = pitch * 1.6;
        var dy = sqrt(d * d - pitch * pitch) + 6; // rows far enough apart for neighbours not to touch
        if (d + dy > box.maxHeight) {
          final k = box.maxHeight / (d + dy);
          d *= k;
          dy *= k;
        }
        final x0 = (box.maxWidth - (20 * pitch + d)) / 2;
        final y0 = (box.maxHeight - (d + dy)) / 2;
        // Bottom player's half (positive) on the left of the bottom player.
        Offset at(int v) => Offset(x0 + (10 - v) * pitch, y0 + (v.isEven ? 0 : dy));
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _GaugeLine([for (var v = -10; v <= 10; v++) at(v) + Offset(d / 2, d / 2)])),
            ),
            for (var v = -10; v <= 10; v++)
              Positioned(left: at(v).dx, top: at(v).dy, width: d, height: d, child: _cell(v, d)),
          ],
        );
      },
    );
  }

  Widget _cell(int v, double d) {
    final active = _m.value == v;
    final side = v > 0 ? Side.bottom : (v < 0 ? Side.top : null);
    final color = side == null ? Z.text : _color(side);
    final fill = side == null ? _color(_m.turn) : color;
    final n = v.abs();
    final label = Text(
      '$n',
      style: TextStyle(
        fontSize: (d * .44).clamp(10, 34),
        height: 1,
        fontWeight: FontWeight.w800,
        color: active ? Z.ink : color.withValues(alpha: side == null ? .95 : .9),
        fontFeatures: Z.tabular,
      ),
    );
    return GestureDetector(
      key: ValueKey('cell$v'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _apply(_m.setTo(v)),
      child: AnimatedScale(
        scale: active ? 1.1 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Opaque, so the connecting line never shows through a circle.
            color: active
                ? fill
                : Color.alphaBlend(color.withValues(alpha: side == null ? .12 : (.08 + n * .014)), Z.ink),
            border: Border.all(
              color: active ? fill : color.withValues(alpha: side == null ? .7 : .5),
              width: v == 0 ? 2.5 : 2,
            ),
            boxShadow: active ? [BoxShadow(color: fill.withValues(alpha: .65), blurRadius: 22)] : null,
          ),
          alignment: Alignment.center,
          // Each half's numbers face the player who owns it.
          child: side == Side.top ? RotatedBox(quarterTurns: 2, child: label) : label,
        ),
      ),
    );
  }

  Widget _btn(
    Color color,
    String text,
    VoidCallback? on, {
    bool primary = false,
    IconData? icon,
    int flex = 2,
    Key? key,
  }) => Expanded(
    flex: flex,
    child: Opacity(
      opacity: on == null ? .28 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: primary ? color : color.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(11),
            onTap: on,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[Icon(icon, size: 16, color: primary ? Z.ink : color), const SizedBox(width: 3)],
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        text,
                        textDirection: icon == null && !primary ? TextDirection.ltr : null,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: primary ? Z.ink : color,
                          fontFeatures: Z.tabular,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// One player's strip, along their long edge of the phone.
  Widget _panel(Side s) {
    final mine = _m.turn == s;
    final color = _color(s);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: 66,
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: mine ? color.withValues(alpha: .12) : Z.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mine ? color : Z.line, width: mine ? 2 : 1),
      ),
      child: _paying == s ? _payPad(s) : _controls(s),
    );
  }

  /// "Pay": pick the cost, it comes off this player's memory in one tap.
  Widget _payPad(Side s) {
    final color = _color(s);
    return Row(
      textDirection: TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Center(
            child: Text(
              S.t.payHowMuch,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color),
            ),
          ),
        ),
        Expanded(
          child: Column(
            children: [
              for (var row = 0; row < 2; row++) ...[
                if (row > 0) const SizedBox(height: 4),
                Expanded(
                  child: Row(
                    textDirection: TextDirection.ltr,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var n = row * 10 + 1; n <= row * 10 + 10; n++)
                        // A cost past the opponent's 10 can't be paid.
                        _btn(color, '$n', _m.canPay(s, n) ? () => _pay(s, n) : null, key: ValueKey('pay-${s.name}-$n')),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        IconButton(
          tooltip: S.t.cancel,
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _paying = null),
          icon: const Icon(Icons.close),
          color: Z.muted,
        ),
      ],
    );
  }

  Widget _controls(Side s) {
    final mine = _m.turn == s;
    final color = _color(s);
    final mem = _m.memoryFor(s);
    final wins = s == Side.bottom ? _bottomWins : _topWins;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 104,
          child: GestureDetector(
            onTap: () => _rename(s),
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _name(s),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color),
                ),
                Text(
                  mine ? S.t.yourTurn : S.t.waiting,
                  maxLines: 1,
                  style: TextStyle(fontSize: 12, color: mine ? Z.text : Z.muted, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        // Games won (best of three) and the button that records one.
        InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => _gameWon(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: color.withValues(alpha: .5)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.emoji_events_rounded, size: 15, color: color),
                    const SizedBox(width: 3),
                    Text(
                      S.t.winShort,
                      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12.5),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 2; i++)
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < wins ? color : Colors.transparent,
                          border: Border.all(color: color.withValues(alpha: .6), width: 1.5),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 58,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              mem > 0 ? '$mem' : (mem == 0 ? '0' : '−${-mem}'),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 34,
                height: 1,
                fontWeight: FontWeight.w800,
                color: mem >= 0 ? Z.text : Z.muted,
                fontFeatures: Z.tabular,
              ),
            ),
          ),
        ),
        Expanded(
          child: Row(
            textDirection: TextDirection.ltr,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _btn(color, '−3', _m.canPay(s, 3) ? () => _apply(_m.adjust(s, -3)) : null),
              _btn(color, '−2', _m.canPay(s, 2) ? () => _apply(_m.adjust(s, -2)) : null),
              _btn(color, '−1', _m.canPay(s, 1) ? () => _apply(_m.adjust(s, -1)) : null),
              _btn(color, '+1', () => _apply(_m.adjust(s, 1))),
              _btn(color, S.t.pay, () => setState(() => _paying = s), icon: Icons.bolt_rounded, flex: 3),
              if (mine)
                _btn(color, S.t.endTurn, () => _apply(_m.endTurn()), primary: true, flex: 4)
              else
                _btn(color, '+2', () => _apply(_m.adjust(s, 2)), flex: 4),
            ],
          ),
        ),
      ],
    );
  }
}

/// The faint line that strings the gauge's circles together, in order.
class _GaugeLine extends CustomPainter {
  final List<Offset> centres;
  const _GaugeLine(this.centres);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(centres.first.dx, centres.first.dy);
    for (final c in centres.skip(1)) {
      path.lineTo(c.dx, c.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Z.line,
    );
  }

  @override
  bool shouldRepaint(_GaugeLine old) => old.centres.length != centres.length || old.centres.first != centres.first;
}

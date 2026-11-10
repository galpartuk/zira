import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../engine/memory.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Digimon Card Game memory gauge for two players facing each other across
/// the phone. The top player's half is rotated so it reads right way up for
/// them. Tap any cell to move the marker there; the turn passes on its own
/// when the memory lands on the opponent's side.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  static const _prefsKey = 'zira.memory.v1';

  MemoryState _m = const MemoryState();
  final List<MemoryState> _undo = [];
  String _bottomName = 'שחקן כחול';
  String _topName = 'שחקן כתום';
  int _bottomWins = 0, _topWins = 0;

  String? _banner;
  Side _bannerSide = Side.bottom;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _load();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_prefsKey);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _m = MemoryState.fromJson(j['m'] as Map<String, dynamic>);
        _bottomName = j['bn'] as String? ?? _bottomName;
        _topName = j['tn'] as String? ?? _topName;
        _bottomWins = j['bw'] as int? ?? 0;
        _topWins = j['tw'] as int? ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _prefsKey,
        jsonEncode({
          'm': _m.toJson(),
          'bn': _bottomName,
          'tn': _topName,
          'bw': _bottomWins,
          'tw': _topWins,
        }));
  }

  String _name(Side s) => s == Side.bottom ? _bottomName : _topName;
  Color _color(Side s) => s == Side.bottom ? Z.blue : Z.coral;

  void _apply(MemoryState next) {
    if (next.value == _m.value && next.turn == _m.turn && next.turnNumber == _m.turnNumber) return;
    final passed = next.turn != _m.turn;
    _undo.add(_m);
    if (_undo.length > 200) _undo.removeAt(0);
    setState(() => _m = next);
    if (passed) {
      HapticFeedback.heavyImpact();
      _showBanner('התור של ${_name(next.turn)}', next.turn);
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
    _showBanner('${_name(_m.turn)} מתחיל', _m.turn);
    _save();
  }

  Future<void> _menu() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.casino),
              title: const Text('משחק חדש — הגרלה מי מתחיל'),
              onTap: () => Navigator.pop(c, 'roll')),
          ListTile(
              leading: const Icon(Icons.south, color: Z.blue),
              title: Text('משחק חדש — $_bottomName מתחיל'),
              onTap: () => Navigator.pop(c, 'bottom')),
          ListTile(
              leading: const Icon(Icons.north, color: Z.coral),
              title: Text('משחק חדש — $_topName מתחיל'),
              onTap: () => Navigator.pop(c, 'top')),
          ListTile(
              leading: const Icon(Icons.swap_vert),
              title: const Text('העברת התור ידנית'),
              onTap: () => Navigator.pop(c, 'swap')),
          ListTile(
              leading: const Icon(Icons.exposure_zero),
              title: const Text('איפוס ניצחונות'),
              onTap: () => Navigator.pop(c, 'wins')),
        ]),
      ),
    );
    switch (v) {
      case 'roll':
        _rollFirst();
      case 'bottom':
        _newGame(first: Side.bottom);
      case 'top':
        _newGame(first: Side.top);
      case 'swap':
        _apply(MemoryState(value: _m.value, turn: _m.turn.other, turnNumber: _m.turnNumber + 1));
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
    _showBanner('🎲 $a מול $b — ${_name(_m.turn)} מתחיל', _m.turn);
  }

  Future<void> _rename(Side s) async {
    final v = await promptText(context, 'שם השחקן', initial: _name(s));
    if (v == null || v.isEmpty) return;
    setState(() => s == Side.bottom ? _bottomName = v : _topName = v);
    _save();
  }

  Future<void> _gameWon(Side s) async {
    final ok = await confirm(context, '${_name(s)} ניצח במשחק?', 'יתווסף ניצחון ויתחיל משחק חדש. המפסיד מתחיל במשחק הבא.',
        ok: 'כן, משחק חדש');
    if (!ok) return;
    setState(() => s == Side.bottom ? _bottomWins++ : _topWins++);
    _newGame(first: s.other);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Z.ink,
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            RotatedBox(quarterTurns: 2, child: _panel(Side.top)),
            Expanded(
              child: Row(children: [
                Expanded(child: _gauge()),
                _rail(),
              ]),
            ),
            _panel(Side.bottom),
          ]),
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
                        child: Text(_banner!,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Z.ink)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _rail() {
    Widget b(IconData i, String tip, VoidCallback? on) => IconButton(
          tooltip: tip,
          onPressed: on,
          icon: Icon(i, size: 24),
          color: Z.muted,
        );
    return SizedBox(
      width: 52,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        b(Icons.close, 'יציאה', () => Navigator.pop(context)),
        const SizedBox(height: 12),
        b(Icons.undo, 'ביטול פעולה', _undo.isEmpty ? null : _doUndo),
        b(Icons.casino_outlined, 'משחק חדש', _menu),
        const SizedBox(height: 12),
        RotatedBox(
          quarterTurns: 3,
          child: Text('תור ${_m.turnNumber}',
              style: const TextStyle(color: Z.muted, fontWeight: FontWeight.w700, fontFeatures: Z.tabular)),
        ),
      ]),
    );
  }

  Widget _gauge() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 0, 6),
      child: LayoutBuilder(builder: (context, box) {
        final h = box.maxHeight / 21;
        return Column(children: [
          for (var v = -10; v <= 10; v++) _cell(v, h),
        ]);
      }),
    );
  }

  Widget _cell(int v, double h) {
    final active = _m.value == v;
    final side = v > 0 ? Side.bottom : (v < 0 ? Side.top : null);
    final color = side == null ? Z.text : _color(side);
    final turnColor = _color(_m.turn);
    final n = v.abs();
    final label = Text(
      '$n',
      style: TextStyle(
        fontSize: (h * .52).clamp(11, 22),
        fontWeight: active ? FontWeight.w800 : FontWeight.w700,
        color: active ? Z.ink : color.withValues(alpha: side == null ? .9 : .75),
        fontFeatures: Z.tabular,
      ),
    );
    return SizedBox(
      height: h,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: max(1, h * .06)),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _apply(_m.setTo(v)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            margin: EdgeInsets.symmetric(horizontal: active ? 0 : 14),
            decoration: BoxDecoration(
              color: active
                  ? (side == null ? turnColor : color)
                  : color.withValues(alpha: side == null ? .16 : (.05 + n * .012)),
              borderRadius: BorderRadius.circular(8),
              border: v == 0 && !active ? Border.all(color: Z.text.withValues(alpha: .35)) : null,
              boxShadow: active
                  ? [BoxShadow(color: (side == null ? turnColor : color).withValues(alpha: .55), blurRadius: 18)]
                  : null,
            ),
            alignment: Alignment.center,
            // Numbers on the top half face the top player.
            child: side == Side.top ? RotatedBox(quarterTurns: 2, child: label) : label,
          ),
        ),
      ),
    );
  }

  Widget _panel(Side s) {
    final mine = _m.turn == s;
    final color = _color(s);
    final mem = _m.memoryFor(s);
    final wins = s == Side.bottom ? _bottomWins : _topWins;

    Widget btn(String text, VoidCallback on, {bool primary = false}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: primary ? color : color.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: on,
                child: SizedBox(
                  height: 46,
                  child: Center(
                    child: Text(text,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: primary ? Z.ink : color,
                            fontFeatures: Z.tabular)),
                  ),
                ),
              ),
            ),
          ),
        );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: mine ? color.withValues(alpha: .12) : Z.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: mine ? color : Z.line, width: mine ? 2 : 1),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _rename(s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_name(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
                Text(mine ? 'התור שלך' : 'ממתין',
                    style: TextStyle(fontSize: 12.5, color: mine ? Z.text : Z.muted, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          GestureDetector(
            onLongPress: () => _gameWon(s),
            child: Tooltip(
              message: 'לחיצה ארוכה: ניצחון במשחק',
              child: Row(children: [
                for (var i = 0; i < 2; i++)
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < wins ? color : Colors.transparent,
                      border: Border.all(color: color.withValues(alpha: .6), width: 1.5),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(mem > 0 ? '$mem' : (mem == 0 ? '0' : '−${-mem}'),
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    fontSize: 30,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: mem >= 0 ? Z.text : Z.muted,
                    fontFeatures: Z.tabular)),
            const Text('זיכרון', style: TextStyle(fontSize: 11, color: Z.muted)),
          ]),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          btn('−3', () => _apply(_m.adjust(s, -3))),
          btn('−1', () => _apply(_m.adjust(s, -1))),
          btn('+1', () => _apply(_m.adjust(s, 1))),
          if (mine)
            btn('סיום תור', () => _apply(_m.pass()), primary: true)
          else
            btn('+2', () => _apply(_m.adjust(s, 2))),
        ]),
      ]),
    );
  }
}

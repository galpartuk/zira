import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'tool_icons.dart';

final _rng = Random.secure();

/// Two modes: free dice (1-4 dice, d4…d20), and "who goes first" — both
/// players roll a d6, higher goes first, ties re-roll (as in Bandai events).
class DiceScreen extends StatefulWidget {
  const DiceScreen({super.key});

  @override
  State<DiceScreen> createState() => _DiceScreenState();
}

class _DiceScreenState extends State<DiceScreen> {
  bool _firstMode = true;
  int _count = 1;
  int _sides = 6;
  List<int> _values = [6];
  bool _rolling = false;
  Timer? _anim;
  int _spin = 0;

  // who-goes-first
  int _a = 0, _b = 0;
  String? _verdict;

  @override
  void dispose() {
    _anim?.cancel();
    super.dispose();
  }

  void _roll() {
    if (_rolling) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _rolling = true;
      _verdict = null;
      _spin++;
    });
    var ticks = 0;
    _anim = Timer.periodic(const Duration(milliseconds: 70), (t) {
      ticks++;
      setState(() {
        if (_firstMode) {
          _a = _rng.nextInt(6) + 1;
          _b = _rng.nextInt(6) + 1;
        } else {
          _values = List.generate(_count, (_) => _rng.nextInt(_sides) + 1);
        }
      });
      if (ticks >= 10) {
        t.cancel();
        HapticFeedback.heavyImpact();
        setState(() {
          _rolling = false;
          if (_firstMode) {
            if (_a == _b) {
              _verdict = 'שוויון — מטילים שוב';
            } else {
              _verdict = _a > _b ? 'שחקן כחול מתחיל' : 'שחקן כתום מתחיל';
            }
          }
        });
      }
    });
  }

  Widget _die(int v, double size, {Color color = Z.text}) {
    return AnimatedRotation(
      turns: _rolling ? _spin * 1.0 + .5 : _spin * 1.0,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutBack,
      child: _sides == 6 || _firstMode
          ? DieFace(value: v == 0 ? 1 : v, size: size, color: color)
          : PolyDie(sides: _sides, value: v, size: size, color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('קוביות')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, label: Text('מי מתחיל?')),
              ButtonSegment(value: false, label: Text('הטלה חופשית')),
            ],
            selected: {_firstMode},
            onSelectionChanged: (s) => setState(() {
              _firstMode = s.first;
              _verdict = null;
              _a = _b = 0;
            }),
          ),
        ),
        if (!_firstMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              const Text('כמה:', style: TextStyle(color: Z.muted)),
              const SizedBox(width: 8),
              for (final n in [1, 2, 3, 4])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    label: Text('$n'),
                    selected: _count == n,
                    showCheckmark: false,
                    selectedColor: Z.gold,
                    labelStyle: TextStyle(color: _count == n ? Z.ink : Z.text, fontWeight: FontWeight.w700),
                    onSelected: (_) => setState(() {
                      _count = n;
                      _values = List.generate(n, (_) => _sides);
                    }),
                  ),
                ),
              const Spacer(),
              DropdownButton<int>(
                value: _sides,
                underline: const SizedBox(),
                items: [4, 6, 8, 10, 12, 20].map((s) => DropdownMenuItem(value: s, child: Text('d$s'))).toList(),
                onChanged: (s) => setState(() {
                  _sides = s!;
                  _values = List.generate(_count, (_) => _sides);
                }),
              ),
            ]),
          ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _roll,
            child: Center(child: _firstMode ? _firstView() : _freeView()),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _rolling ? null : _roll,
                icon: const Icon(Icons.casino),
                label: const Text('הטלה'),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _freeView() {
    final size = _count == 1 ? 150.0 : (_count == 2 ? 120.0 : 100.0);
    final total = _values.fold<int>(0, (a, b) => a + b);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Wrap(
        spacing: 22,
        runSpacing: 22,
        alignment: WrapAlignment.center,
        children: [for (final v in _values) _die(v, size, color: _sides == 6 ? Z.text : Z.gold)],
      ),
      const SizedBox(height: 28),
      if (_count > 1)
        Text('סה״כ $total',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, fontFeatures: Z.tabular)),
      const SizedBox(height: 6),
      const Text('הקישו בכל מקום להטלה', style: TextStyle(color: Z.muted)),
    ]);
  }

  Widget _firstView() {
    Widget side(String who, int v, Color c, bool won) => Column(mainAxisSize: MainAxisSize.min, children: [
          Text(who, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 14),
          AnimatedScale(
            scale: won ? 1.12 : (_verdict != null && !won && _a != _b ? .88 : 1),
            duration: const Duration(milliseconds: 300),
            child: Opacity(
              opacity: v == 0 ? .35 : 1,
              child: _die(v, 116, color: c),
            ),
          ),
        ]);
    final done = _verdict != null && _a != _b;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        side('כחול', _a, Z.blue, done && _a > _b),
        side('כתום', _b, Z.coral, done && _b > _a),
      ]),
      const SizedBox(height: 36),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Text(
          _verdict ?? (_a == 0 ? 'כל שחקן מקבל קובייה. הגבוהה מתחילה.' : '...'),
          key: ValueKey(_verdict),
          style: TextStyle(
            fontSize: _verdict == null ? 15 : 26,
            fontWeight: FontWeight.w800,
            color: _verdict == null ? Z.muted : (_a == _b ? Z.gold : (_a > _b ? Z.blue : Z.coral)),
          ),
        ),
      ),
    ]);
  }
}

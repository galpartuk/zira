import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../theme.dart';

final _rng = Random.secure();

enum Hand { rock, paper, scissors }

extension HandX on Hand {
  String get emoji => const ['✊', '✋', '✌️'][index];
  String get label => S.t.hands[index];
  bool beats(Hand o) => (index - o.index + 3) % 3 == 1;
}

enum _Phase { pickA, handOff, pickB, countdown, reveal }

/// Rock-paper-scissors. Two players on one phone pick in secret (pass the
/// phone between picks), or one player against the phone.
class RpsScreen extends StatefulWidget {
  const RpsScreen({super.key});

  @override
  State<RpsScreen> createState() => _RpsScreenState();
}

class _RpsScreenState extends State<RpsScreen> {
  bool _vsPhone = false;
  _Phase _phase = _Phase.pickA;
  Hand? _a, _b;
  int _count = 0;
  Timer? _timer;
  int _scoreA = 0, _scoreB = 0, _draws = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _nameA => _vsPhone ? S.t.you : S.t.blue;
  String get _nameB => _vsPhone ? S.t.phone : S.t.orange;

  void _reset() {
    _timer?.cancel();
    setState(() {
      _phase = _Phase.pickA;
      _a = _b = null;
    });
  }

  void _pick(Hand h) {
    HapticFeedback.selectionClick();
    if (_phase == _Phase.pickA) {
      _a = h;
      if (_vsPhone) {
        _b = Hand.values[_rng.nextInt(3)];
        _countdown();
      } else {
        setState(() => _phase = _Phase.handOff);
      }
    } else if (_phase == _Phase.pickB) {
      _b = h;
      _countdown();
    }
  }

  void _countdown() {
    setState(() {
      _phase = _Phase.countdown;
      _count = 0;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 480), (t) {
      HapticFeedback.lightImpact();
      if (_count >= 2) {
        t.cancel();
        HapticFeedback.heavyImpact();
        setState(() {
          _phase = _Phase.reveal;
          if (_a == _b) {
            _draws++;
          } else if (_a!.beats(_b!)) {
            _scoreA++;
          } else {
            _scoreB++;
          }
        });
      } else {
        setState(() => _count++);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t.rps),
        actions: [
          if (_scoreA + _scoreB + _draws > 0)
            IconButton(
              tooltip: S.t.resetScore,
              onPressed: () => setState(() => _scoreA = _scoreB = _draws = 0),
              icon: const Icon(Icons.restart_alt),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(S.t.twoPlayers)),
                ButtonSegment(value: true, label: Text(S.t.vsPhone)),
              ],
              selected: {_vsPhone},
              onSelectionChanged: (s) {
                _vsPhone = s.first;
                _scoreA = _scoreB = _draws = 0;
                _reset();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _score(_nameA, _scoreA, Z.blue),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Text(
                    S.t.draws(_draws),
                    style: TextStyle(color: Z.muted, fontFeatures: Z.tabular),
                  ),
                ),
                _score(_nameB, _scoreB, Z.coral),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: _body()),
          ),
        ],
      ),
    );
  }

  Widget _score(String name, int v, Color c) => Column(
    children: [
      Text(
        name,
        style: TextStyle(color: c, fontWeight: FontWeight.w700),
      ),
      Text(
        '$v',
        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, fontFeatures: Z.tabular),
      ),
    ],
  );

  Widget _body() {
    switch (_phase) {
      case _Phase.pickA:
      case _Phase.pickB:
        final a = _phase == _Phase.pickA;
        final color = a ? Z.blue : Z.coral;
        return Column(
          key: ValueKey(_phase),
          children: [
            Text(
              _vsPhone ? S.t.pickHand : S.t.pickSecret(a ? _nameA : _nameB),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  children: [
                    for (final h in Hand.values)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: color.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => _pick(h),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(h.emoji, style: const TextStyle(fontSize: 46)),
                                  const SizedBox(width: 18),
                                  SizedBox(
                                    width: 110,
                                    child: Text(
                                      h.label,
                                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      case _Phase.handOff:
        return Padding(
          key: const ValueKey('handoff'),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 54, color: Z.blue),
              const SizedBox(height: 12),
              Text(
                S.t.passPhone(_nameA, _nameB),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Z.coral, foregroundColor: Z.ink),
                onPressed: () => setState(() => _phase = _Phase.pickB),
                child: Text(S.t.iAm(_nameB)),
              ),
            ],
          ),
        );
      case _Phase.countdown:
        return Center(
          key: ValueKey('c$_count'),
          child: Text(
            S.t.countdown[_count],
            style: TextStyle(fontSize: 46, fontWeight: FontWeight.w700, color: Z.accent),
          ),
        );
      case _Phase.reveal:
        final a = _a!, b = _b!;
        final String verdict;
        final Color vc;
        if (a == b) {
          verdict = S.t.drawBang;
          vc = Z.accent;
        } else if (a.beats(b)) {
          verdict = _vsPhone ? S.t.youWin : S.t.wins(_nameA);
          vc = Z.blue;
        } else {
          verdict = S.t.wins(_nameB);
          vc = Z.coral;
        }
        return Column(
          key: const ValueKey('reveal'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _revealHand(a, _nameA, Z.blue, a != b && a.beats(b)),
                Text(S.t.vs, style: TextStyle(color: Z.muted, fontSize: 16)),
                _revealHand(b, _nameB, Z.coral, a != b && b.beats(a)),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              verdict,
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: vc),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(onPressed: _reset, icon: const Icon(Icons.replay), label: Text(S.t.playAgain)),
          ],
        );
    }
  }

  Widget _revealHand(Hand h, String who, Color c, bool won) => TweenAnimationBuilder<double>(
    tween: Tween(begin: .4, end: won ? 1.15 : 1),
    duration: const Duration(milliseconds: 420),
    curve: Curves.elasticOut,
    builder: (_, s, child) => Transform.scale(scale: s, child: child),
    child: Column(
      children: [
        Container(
          width: 124,
          height: 124,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.withValues(alpha: won ? .28 : .1),
            border: Border.all(color: won ? c : Colors.transparent, width: 3),
          ),
          child: Text(h.emoji, style: const TextStyle(fontSize: 62)),
        ),
        const SizedBox(height: 8),
        Text(
          who,
          style: TextStyle(color: c, fontWeight: FontWeight.w700),
        ),
        Text(h.label, style: TextStyle(color: Z.muted)),
      ],
    ),
  );
}

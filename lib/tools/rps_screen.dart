import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

final _rng = Random.secure();

enum Hand { rock, paper, scissors }

extension HandX on Hand {
  String get emoji => const ['✊', '✋', '✌️'][index];
  String get label => const ['אבן', 'נייר', 'מספריים'][index];
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

  String get _nameA => _vsPhone ? 'אתם' : 'כחול';
  String get _nameB => _vsPhone ? 'הטלפון' : 'כתום';

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
        title: const Text('אבן נייר ומספריים'),
        actions: [
          if (_scoreA + _scoreB + _draws > 0)
            IconButton(
              tooltip: 'איפוס ניקוד',
              onPressed: () => setState(() => _scoreA = _scoreB = _draws = 0),
              icon: const Icon(Icons.restart_alt),
            ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('שני שחקנים')),
              ButtonSegment(value: true, label: Text('נגד הטלפון')),
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
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _score(_nameA, _scoreA, Z.blue),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text('תיקו $_draws', style: const TextStyle(color: Z.muted, fontFeatures: Z.tabular)),
            ),
            _score(_nameB, _scoreB, Z.coral),
          ]),
        ),
        Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: _body())),
      ]),
    );
  }

  Widget _score(String name, int v, Color c) => Column(children: [
        Text(name, style: TextStyle(color: c, fontWeight: FontWeight.w800)),
        Text('$v', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, fontFeatures: Z.tabular)),
      ]);

  Widget _body() {
    switch (_phase) {
      case _Phase.pickA:
      case _Phase.pickB:
        final a = _phase == _Phase.pickA;
        final color = a ? Z.blue : Z.coral;
        return Column(key: ValueKey(_phase), children: [
          Text(_vsPhone ? 'בחרו יד' : 'תור ${a ? _nameA : _nameB} לבחור — בלי שהשני יראה',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 18),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(children: [
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
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(h.emoji, style: const TextStyle(fontSize: 46)),
                            const SizedBox(width: 18),
                            SizedBox(
                                width: 110,
                                child: Text(h.label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ]);
      case _Phase.handOff:
        return Padding(
          key: const ValueKey('handoff'),
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.lock_outline, size: 54, color: Z.blue),
            const SizedBox(height: 12),
            Text('$_nameA בחר. מעבירים את הטלפון ל$_nameB.',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Z.coral, foregroundColor: Z.ink),
              onPressed: () => setState(() => _phase = _Phase.pickB),
              child: Text('אני $_nameB — להמשיך'),
            ),
          ]),
        );
      case _Phase.countdown:
        return Center(
          key: ValueKey('c$_count'),
          child: Text(['אבן...', 'נייר...', 'מספריים!'][_count],
              style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w800, color: Z.gold)),
        );
      case _Phase.reveal:
        final a = _a!, b = _b!;
        final String verdict;
        final Color vc;
        if (a == b) {
          verdict = 'תיקו!';
          vc = Z.gold;
        } else if (a.beats(b)) {
          verdict = _vsPhone ? 'ניצחתם!' : '$_nameA ניצח!';
          vc = Z.blue;
        } else {
          verdict = '$_nameB ניצח!';
          vc = Z.coral;
        }
        return Column(key: const ValueKey('reveal'), mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _revealHand(a, _nameA, Z.blue, a != b && a.beats(b)),
            const Text('נגד', style: TextStyle(color: Z.muted, fontSize: 16)),
            _revealHand(b, _nameB, Z.coral, a != b && b.beats(a)),
          ]),
          const SizedBox(height: 28),
          Text(verdict, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: vc)),
          const SizedBox(height: 28),
          FilledButton.icon(onPressed: _reset, icon: const Icon(Icons.replay), label: const Text('עוד סיבוב')),
        ]);
    }
  }

  Widget _revealHand(Hand h, String who, Color c, bool won) => TweenAnimationBuilder<double>(
        tween: Tween(begin: .4, end: won ? 1.15 : 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.elasticOut,
        builder: (_, s, child) => Transform.scale(scale: s, child: child),
        child: Column(children: [
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
          Text(who, style: TextStyle(color: c, fontWeight: FontWeight.w800)),
          Text(h.label, style: const TextStyle(color: Z.muted)),
        ]),
      );
}

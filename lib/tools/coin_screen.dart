import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../theme.dart';

final _rng = Random.secure();

/// Coin flip with a 3D spin. Heads (עץ) or tails (פלי).
class CoinScreen extends StatefulWidget {
  const CoinScreen({super.key});

  @override
  State<CoinScreen> createState() => _CoinScreenState();
}

class _CoinScreenState extends State<CoinScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  double _from = 0, _to = 0; // in half-turns
  bool _heads = true;
  bool _shown = false;
  final List<bool> _history = [];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _flip() {
    if (_ctrl.isAnimating) return;
    HapticFeedback.mediumImpact();
    final heads = _rng.nextBool();
    // Even number of half turns lands on heads.
    final base = _to.roundToDouble();
    var target = base + 8 + _rng.nextInt(3) * 2;
    if ((target.round().isEven) != heads) target += 1;
    setState(() {
      _from = _to;
      _to = target;
      _heads = heads;
      _shown = false;
    });
    _ctrl.forward(from: 0).whenComplete(() {
      HapticFeedback.heavyImpact();
      setState(() {
        _shown = true;
        _history.insert(0, heads);
        if (_history.length > 20) _history.removeLast();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final heads = _history.where((h) => h).length;
    return Scaffold(
      appBar: AppBar(title: Text(S.t.coin)),
      body: Column(children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _flip,
            child: Center(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final t = Curves.easeOutCubic.transform(_ctrl.value);
                  final halfTurns = _from + (_to - _from) * t;
                  final angle = halfTurns * pi;
                  final lift = sin(t * pi) * 120;
                  final showHeads = (halfTurns + .5).floor().isEven;
                  return Transform.translate(
                    offset: Offset(0, -lift),
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, .0015)
                        ..rotateX(angle),
                      // The back face is seen through a half turn: flip it
                      // so "tails" reads correctly.
                      child: showHeads
                          ? const _CoinFace(heads: true)
                          : Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.rotationX(pi),
                              child: const _CoinFace(heads: false),
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        AnimatedOpacity(
          opacity: _shown ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Text(_heads ? S.t.heads : S.t.tails,
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: Z.gold)),
        ),
        const SizedBox(height: 14),
        if (_history.isNotEmpty) ...[
          Text(S.t.coinTally(heads, _history.length - heads, _history.length),
              style: const TextStyle(color: Z.muted, fontFeatures: Z.tabular)),
          const SizedBox(height: 8),
          Wrap(spacing: 5, runSpacing: 5, alignment: WrapAlignment.center, children: [
            for (final h in _history)
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: h ? Z.gold.withValues(alpha: .85) : const Color(0xFFB9C3CE)),
                child: Text(h ? S.t.headsLetter : S.t.tailsLetter, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Z.ink)),
              ),
          ]),
        ],
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(onPressed: _flip, icon: const Icon(Icons.flip), label: Text(S.t.flip)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _CoinFace extends StatelessWidget {
  final bool heads;
  const _CoinFace({required this.heads});

  @override
  Widget build(BuildContext context) {
    final colors = heads
        ? const [Color(0xFFFFE6A0), Color(0xFFE2AE3E), Color(0xFFA9781E)]
        : const [Color(0xFFF2F5F8), Color(0xFFB7C2CD), Color(0xFF7B8794)];
    final ink = heads ? const Color(0xFF6B4D10) : const Color(0xFF3B4652);
    return Container(
      width: 210,
      height: 210,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .35), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      padding: const EdgeInsets.all(12),
      child: Container(
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ink.withValues(alpha: .45), width: 3)),
        alignment: Alignment.center,
        child: heads
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.park_rounded, size: 76, color: ink),
                Text(S.t.heads, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: ink)),
              ])
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text('1', style: TextStyle(fontSize: 84, height: 1, fontWeight: FontWeight.w800, color: ink)),
                Text(S.t.tails, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: ink)),
              ]),
      ),
    );
  }
}

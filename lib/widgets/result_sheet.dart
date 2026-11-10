import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../l10n.dart';
import '../theme.dart';

/// Bottom sheet for reporting a match. Returns the chosen result, or
/// [ResultSheet.clear] to remove a result.
class ResultSheet extends StatelessWidget {
  static const clear = MatchResult(Outcome.draw, -1, -1);

  final String p1;
  final String p2;
  final int bestOf;
  final bool elimination; // top cut: a winner is required
  final MatchResult? current;

  const ResultSheet({
    super.key,
    required this.p1,
    required this.p2,
    required this.bestOf,
    required this.elimination,
    this.current,
  });

  @override
  Widget build(BuildContext context) {
    void pick(MatchResult r) => Navigator.pop(context, r);

    Widget winBtn(String text, Color color, MatchResult r, {bool big = false}) {
      final selected = current != null &&
          current!.outcome == r.outcome &&
          current!.g1 == r.g1 &&
          current!.g2 == r.g2;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Material(
            color: selected ? color : color.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => pick(r),
              child: Container(
                height: big ? 64 : 52,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(text,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: big ? 16 : 15,
                        color: selected ? Z.ink : color,
                        fontFeatures: Z.tabular)),
              ),
            ),
          ),
        ),
      );
    }

    final bo3 = bestOf > 1;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text(p1,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Z.blue))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(S.t.vs, style: const TextStyle(color: Z.muted)),
            ),
            Expanded(
                child: Text(p2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Z.coral))),
          ]),
          const SizedBox(height: 14),
          if (!bo3)
            Row(children: [
              winBtn(S.t.won(p1), Z.blue, const MatchResult(Outcome.p1, 1, 0), big: true),
              winBtn(S.t.won(p2), Z.coral, const MatchResult(Outcome.p2, 0, 1), big: true),
            ])
          else ...[
            Row(children: [
              winBtn('2-0', Z.blue, const MatchResult(Outcome.p1, 2, 0), big: true),
              winBtn('0-2', Z.coral, const MatchResult(Outcome.p2, 0, 2), big: true),
            ]),
            Row(children: [
              winBtn('2-1', Z.blue, const MatchResult(Outcome.p1, 2, 1)),
              winBtn('1-2', Z.coral, const MatchResult(Outcome.p2, 1, 2)),
            ]),
            Row(children: [
              winBtn('1-0', Z.blue, const MatchResult(Outcome.p1, 1, 0)),
              winBtn('0-1', Z.coral, const MatchResult(Outcome.p2, 0, 1)),
            ]),
          ],
          if (!elimination) ...[
            const SizedBox(height: 6),
            Row(children: [
              if (bo3) winBtn(S.t.drawScore('1-1'), Z.muted, const MatchResult(Outcome.draw, 1, 1)),
              winBtn(S.t.drawScore('0-0'), Z.muted, const MatchResult(Outcome.draw, 0, 0)),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              child: Text(S.t.drawNote, style: const TextStyle(color: Z.muted, fontSize: 12.5)),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
              child: Text(
                S.t.topTimeoutRule,
                style: const TextStyle(color: Z.muted, fontSize: 12.5, height: 1.45),
              ),
            ),
          if (current != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => pick(clear),
              icon: const Icon(Icons.undo, size: 18),
              label: Text(S.t.clearResult),
            ),
          ],
        ]),
      ),
    );
  }
}

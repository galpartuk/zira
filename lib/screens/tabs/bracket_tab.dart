import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/models.dart';
import '../../engine/pairing.dart';
import '../../engine/standings.dart';
import '../../l10n.dart';
import '../../state/app_state.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/result_sheet.dart';

/// Single-elimination bracket. Before the cut it previews the bracket from the
/// current standings.
class BracketTab extends StatelessWidget {
  final Tournament t;

  /// Players' view: no result entry.
  final bool readOnly;
  const BracketTab({super.key, required this.t, this.readOnly = false});

  static const double _cardH = 84;
  static const double _gap = 16;
  static const double _colW = 168;
  static const double _link = 22;

  @override
  Widget build(BuildContext context) {
    final size = effectiveTopCut(t);
    if (size == 0) {
      return EmptyState(icon: Icons.account_tree_outlined, title: S.t.noTopCut, body: S.t.noTopCutBody);
    }
    final tops = t.topRoundsList;
    final preview = tops.isEmpty;
    final seeds = <String, int>{};
    if (preview) {
      final q = topCutQualifiers(t);
      for (var i = 0; i < q.length; i++) {
        seeds[q[i]] = i + 1;
      }
    } else {
      final st = computeStandings(t);
      final inCut = tops.first.matches.expand((m) => [m.p1, m.p2]).whereType<String>().toSet();
      var k = 1;
      for (final s in st) {
        if (inCut.contains(s.player.id)) seeds[s.player.id] = k++;
      }
    }

    final columns = <List<Match?>>[];
    var count = size ~/ 2;
    var r = 0;
    while (count >= 1) {
      if (r < tops.length) {
        columns.add(tops[r].matches.where((m) => !m.thirdPlace).cast<Match?>().toList());
      } else if (r == 0) {
        columns.add(firstTopRound(t).matches.cast<Match?>().toList());
      } else {
        columns.add(List<Match?>.filled(count, null));
      }
      count ~/= 2;
      r++;
    }
    Match? third;
    for (final rd in tops) {
      for (final m in rd.matches) {
        if (m.thirdPlace) third = m;
      }
    }
    final champion = topCutFinished(t) ? tops.last.matches.firstWhere((m) => !m.thirdPlace).winner : null;
    final height = (size / 2) * (_cardH + _gap);
    final names = [for (var i = 0; i < columns.length; i++) S.t.topRoundName(size >> i)];

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
      children: [
        if (champion != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Z.accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Z.accent, width: 1.5),
            ),
            child: Row(
              children: [
                Icon(Icons.emoji_events, color: Z.accent, size: 38),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.t.tournamentChampion,
                      style: TextStyle(color: Z.muted, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      t.nameOf(champion),
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Z.accent),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (preview)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(S.t.bracketPreview, style: TextStyle(color: Z.muted, fontSize: 13)),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < columns.length; c++) ...[
                SizedBox(
                  width: _colW,
                  child: Column(
                    children: [
                      Text(
                        names[c],
                        style: TextStyle(fontWeight: FontWeight.w700, color: Z.muted),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: height,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            for (final m in columns[c])
                              _BracketMatch(
                                t: t,
                                m: m,
                                seeds: seeds,
                                height: _cardH,
                                preview: preview,
                                editable: !readOnly && !preview && !t.finished && c == tops.length - 1,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (c < columns.length - 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 30),
                    child: CustomPaint(
                      size: Size(_link, height),
                      painter: _Connector(columns[c].length, Directionality.of(context)),
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (third != null || (t.thirdPlace && size >= 4))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.t.thirdPlaceMatch,
                  style: TextStyle(fontWeight: FontWeight.w700, color: Z.muted),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: _colW,
                  child: _BracketMatch(
                    t: t,
                    m: third,
                    seeds: seeds,
                    height: _cardH,
                    preview: preview,
                    editable: !readOnly && third != null && !t.finished && tops.last.matches.contains(third),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BracketMatch extends StatelessWidget {
  final Tournament t;
  final Match? m;
  final Map<String, int> seeds;
  final double height;
  final bool preview;
  final bool editable;

  const _BracketMatch({
    required this.t,
    required this.m,
    required this.seeds,
    required this.height,
    required this.preview,
    required this.editable,
  });

  @override
  Widget build(BuildContext context) {
    final m = this.m;
    Widget slot(String? id, bool top) {
      final won = m != null && m.winner != null && m.winner == id;
      final lost = m != null && m.winner != null && m.winner != id;
      final res = m?.result;
      String score = '';
      if (res != null && t.topBestOf > 1) score = '${top ? res.g1 : res.g2}';
      return Expanded(
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                id == null ? '' : '${seeds[id] ?? ''}',
                style: TextStyle(fontSize: 11.5, color: Z.muted, fontFeatures: Z.tabular),
              ),
            ),
            Expanded(
              child: Text(
                id == null ? '—' : t.nameOf(id),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: won ? FontWeight.w700 : FontWeight.w600,
                  color: id == null || lost ? Z.muted : (won ? Z.accent : Z.text),
                ),
              ),
            ),
            if (score.isNotEmpty)
              Text(
                score,
                style: TextStyle(fontWeight: FontWeight.w700, color: won ? Z.accent : Z.muted, fontFeatures: Z.tabular),
              ),
            if (won)
              Padding(
                padding: EdgeInsetsDirectional.only(start: 4),
                child: Icon(Icons.check, size: 16, color: Z.accent),
              ),
          ],
        ),
      );
    }

    return SizedBox(
      height: height,
      child: Material(
        color: Z.surface,
        // Material asserts when given both a borderRadius and a shape.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: editable && m != null && !m.done ? Z.accent.withValues(alpha: .6) : Z.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: !editable || m == null
              ? null
              : () async {
                  final r = await showModalBottomSheet<MatchResult>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ResultSheet(
                      p1: t.nameOf(m.p1),
                      p2: t.nameOf(m.p2),
                      bestOf: t.topBestOf,
                      elimination: true,
                      current: m.result,
                    ),
                  );
                  if (r == null || !context.mounted) return;
                  final sync = hostSyncOf(context, listen: false);
                  if (sync != null && m.result == null && sync.isOwnMatch(t, m) && !identical(r, ResultSheet.clear)) {
                    // The host's own match: the opponent confirms it.
                    await sync.reportOwn(t, m, r);
                    return;
                  }
                  context.read<AppState>().setResult(t, m, identical(r, ResultSheet.clear) ? null : r);
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(children: [slot(m?.p1, true), const Divider(height: 1), slot(m?.p2, false)]),
          ),
        ),
      ),
    );
  }
}

/// Bracket lines from each pair of matches to the match they feed.
class _Connector extends CustomPainter {
  final int matches; // in the column before the lines
  final TextDirection dir;
  _Connector(this.matches, this.dir);

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = Z.line
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    // Cards sit at the centres of equal slices (spaceAround).
    double y(int i, int k) => s.height * (2 * i + 1) / (2 * k);
    final from = dir == TextDirection.rtl ? s.width : 0.0;
    final to = s.width - from;
    final mid = s.width / 2;
    for (var j = 0; j < matches ~/ 2; j++) {
      final a = y(2 * j, matches), b = y(2 * j + 1, matches), c = y(j, matches ~/ 2);
      final path = Path()
        ..moveTo(from, a)
        ..lineTo(mid, a)
        ..lineTo(mid, b)
        ..lineTo(from, b)
        ..moveTo(mid, c)
        ..lineTo(to, c);
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_Connector o) => o.matches != matches || o.dir != dir;
}

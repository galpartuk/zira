import 'models.dart';
import 'pairing.dart';

class PrizeLine {
  final int place; // 1-based
  final String label; // "1", "3-4" ...
  final String? playerId;
  final double percent; // effective share after tie-splitting
  final double amount;

  const PrizeLine(this.place, this.label, this.playerId, this.percent, this.amount);
}

class PrizeResult {
  final double gross; // fees + extra
  final double houseAmount; // organiser's cut
  final double net; // to be distributed
  final double distributed; // after rounding
  final double leftover; // net - distributed (rounding remainder)
  final double percentSum; // of the configured table
  final List<PrizeLine> lines;

  const PrizeResult(this.gross, this.houseAmount, this.net, this.distributed, this.leftover, this.percentSum, this.lines);
}

/// Splits the prize pool according to the percentage table.
///
/// * Pool = entry fee × players + extra; the house cut comes off the top.
/// * With [PrizeConfig.splitTies], places that share a bracket group (3-4,
///   5-8...) get the average of the group's percentages, so semifinal losers
///   are paid the same.
/// * Amounts are multiples of [PrizeConfig.step] (1 = whole packs). Floors
///   first, then hands out the remaining steps by largest remainder; a tie
///   group only receives an extra step if every member can get one.
PrizeResult computePrizes(PrizeConfig c, int players, {List<Placement>? placements}) {
  final gross = c.entryFee * players + c.extra;
  final house = gross * c.houseCut / 100;
  final net = (gross - house).clamp(0, double.infinity).toDouble();
  final pctSum = c.percents.fold<double>(0, (a, b) => a + b);

  final paid = c.percents.length;
  // Groups for tie splitting, covering at least the paid places.
  final groups = <List<int>>[]; // lists of 0-based places
  final labels = <int, String>{};
  if (placements != null && placements.isNotEmpty) {
    var i = 0;
    while (i < paid) {
      if (i < placements.length) {
        final p = placements[i];
        final from = p.groupFrom - 1, to = p.groupTo - 1;
        final g = [for (var k = from; k <= to; k++) k];
        groups.add(c.splitTies ? g : [i]);
        if (!c.splitTies) {
          labels[i] = '${i + 1}';
          i++;
          continue;
        }
        for (final k in g) {
          labels[k] = p.label;
        }
        i = to + 1;
      } else {
        groups.add([i]);
        labels[i] = '${i + 1}';
        i++;
      }
    }
  } else {
    for (var i = 0; i < paid; i++) {
      groups.add([i]);
      labels[i] = '${i + 1}';
    }
  }

  final count = groups.isEmpty ? 0 : groups.last.last + 1;
  final eff = List<double>.filled(count, 0);
  for (final g in groups) {
    final sum = g.fold<double>(0, (a, k) => a + (k < paid ? c.percents[k] : 0));
    for (final k in g) {
      eff[k] = sum / g.length;
    }
  }

  final step = c.step <= 0 ? 0.01 : c.step;
  final totalUnits = (net / step + 1e-9).floor();
  final want = [for (final p in eff) net * p / 100 / step];
  final units = [for (final w in want) (w + 1e-9).floor()];
  var left = totalUnits - units.fold<int>(0, (a, b) => a + b);

  // Largest remainder, group by group so tied players stay equal.
  final order = [...groups]..sort((a, b) {
      final fa = want[a.first] - units[a.first], fb = want[b.first] - units[b.first];
      final d = fb.compareTo(fa);
      return d != 0 ? d : a.first.compareTo(b.first);
    });
  for (final g in order) {
    if (left <= 0) break;
    final frac = want[g.first] - units[g.first];
    if (frac <= 1e-9) continue;
    if (g.length <= left) {
      for (final k in g) {
        units[k]++;
      }
      left -= g.length;
    }
  }

  final lines = <PrizeLine>[];
  for (var k = 0; k < count; k++) {
    final amount = double.parse((units[k] * step).toStringAsFixed(2));
    lines.add(PrizeLine(k + 1, labels[k] ?? '${k + 1}',
        placements != null && k < placements.length ? placements[k].playerId : null, eff[k], amount));
  }
  final distributed = lines.fold<double>(0, (a, l) => a + l.amount);
  return PrizeResult(gross, house, net, distributed, double.parse((net - distributed).toStringAsFixed(2)), pctSum, lines);
}

/// Ready-made percentage tables. The UI names them (e.g. "Top 2 · 65/35").
const prizePresets = <List<double>>[
  [100],
  [65, 35],
  [50, 30, 20],
  [40, 25, 17.5, 17.5],
  [30, 20, 12.5, 12.5, 6.25, 6.25, 6.25, 6.25],
];

/// Even split across [places].
List<double> flatPercents(int places) =>
    List.filled(places, double.parse((100 / places).toStringAsFixed(4)));

/// Each place gets [ratio] of the one above it, normalised to 100%.
List<double> steppedPercents(int places, {double ratio = 0.65}) {
  final raw = <double>[];
  var v = 1.0;
  for (var i = 0; i < places; i++) {
    raw.add(v);
    v *= ratio;
  }
  final sum = raw.reduce((a, b) => a + b);
  return [for (final r in raw) double.parse((r / sum * 100).toStringAsFixed(2))];
}

/// Scales the table so it sums to 100%.
List<double> normalisePercents(List<double> p) {
  final sum = p.fold<double>(0, (a, b) => a + b);
  if (sum <= 0) return p;
  return [for (final x in p) double.parse((x / sum * 100).toStringAsFixed(2))];
}

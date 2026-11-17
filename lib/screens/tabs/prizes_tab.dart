import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../engine/models.dart';
import '../../engine/pairing.dart';
import '../../engine/prizes.dart';
import '../../l10n.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Prize pool calculator tied to the tournament's placements. Also used
/// standalone from the tools screen (t == null, manual player count).
class PrizesTab extends StatefulWidget {
  final Tournament? t;
  const PrizesTab({super.key, this.t});

  @override
  State<PrizesTab> createState() => _PrizesTabState();
}

class _PrizesTabState extends State<PrizesTab> {
  late PrizeConfig c;
  int _manualPlayers = 16;

  @override
  void initState() {
    super.initState();
    c = widget.t?.prizes ?? PrizeConfig();
  }

  void _changed() {
    setState(() {});
    if (widget.t != null) context.read<AppState>().changed();
  }

  String money(double v) => S.t.amount(c.unit, v);

  /// Name for a ready-made table, e.g. "Top 2 · 65/35".
  String _presetName(List<double> p) {
    if (p.length == 1) return S.t.presetWinnerTakesAll;
    final top = S.t.top(p.length);
    if (p.length > 4) return top;
    String f(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
    return '$top · ${p.map(f).join('/')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    if (t != null) context.watch<AppState>();
    final players = t?.players.length ?? _manualPlayers;
    final placements = t == null ? null : finalPlacements(t);
    final res = computePrizes(c, players, placements: placements);
    final official = t != null && t.finished;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // ---- pool
        Card(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(S.t.prizePool, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      style: ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: [
                        ButtonSegment(value: PrizeConfig.ils, label: Text(S.t.money)),
                        ButtonSegment(value: PrizeConfig.packs, label: Text(S.t.packsOption)),
                      ],
                      selected: {c.isMoney ? PrizeConfig.ils : PrizeConfig.packs},
                      onSelectionChanged: (s) {
                        c.unit = s.first;
                        c.step = 1;
                        if (c.isMoney && c.entryFee <= 1) c.entryFee = 30;
                        if (!c.isMoney && c.entryFee > 5) c.entryFee = 1;
                        _changed();
                      },
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _NumField(
                        key: ValueKey('fee-${c.unit}'),
                        label: c.isMoney ? S.t.entryFee : S.t.packsPerPlayer,
                        value: c.entryFee,
                        onChanged: (v) {
                          c.entryFee = v;
                          _changed();
                        },
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: _NumField(
                        label: S.t.addedToPool,
                        value: c.extra,
                        onChanged: (v) {
                          c.extra = v;
                          _changed();
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                if (t == null)
                  SettingRow(
                    title: S.t.playerCount,
                    child: Stepper2(
                      value: _manualPlayers,
                      min: 2,
                      max: 512,
                      onChanged: (v) => setState(() => _manualPlayers = v),
                    ),
                  ),
                SettingRow(
                  title: S.t.organiserCut,
                  subtitle: res.houseAmount > 0 ? S.t.organiserKeeps(money(res.houseAmount)) : null,
                  child: Stepper2(
                    value: c.houseCut.round(),
                    max: 100,
                    format: (v) => '$v%',
                    onChanged: (v) {
                      c.houseCut = v.toDouble();
                      _changed();
                    },
                  ),
                ),
                if (c.isMoney)
                  SettingRow(
                    title: S.t.rounding,
                    child: DropdownButton<double>(
                      value: c.step,
                      underline: SizedBox(),
                      items: [1.0, 5.0, 10.0, 50.0]
                          .map((v) => DropdownMenuItem(value: v, child: Text(S.t.roundTo('₪${v.toStringAsFixed(0)}'))))
                          .toList(),
                      onChanged: (v) {
                        c.step = v!;
                        _changed();
                      },
                    ),
                  ),
                if (t != null && t.topCut > 0)
                  SettingRow(
                    title: S.t.splitTies,
                    subtitle: S.t.splitTiesExplain,
                    child: Switch(
                      value: c.splitTies,
                      onChanged: (v) {
                        c.splitTies = v;
                        _changed();
                      },
                    ),
                  ),
                Divider(height: 22),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${S.t.poolFormula(players, money(c.entryFee))}${c.extra > 0 ? ' + ${money(c.extra)}' : ''}${c.houseCut > 0 ? ' − ${c.houseCut.toStringAsFixed(0)}%' : ''}',
                            style: TextStyle(color: Z.muted, fontSize: 13),
                          ),
                          SizedBox(height: 2),
                          Text(
                            money(res.net),
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              color: Z.accent,
                              fontFeatures: Z.tabular,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      S.t.toHandOut,
                      style: TextStyle(color: Z.muted, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ---- presets
        SectionTitle(
          S.t.split,
          trailing: Text(
            S.t.total('${res.percentSum.toStringAsFixed(res.percentSum == res.percentSum.roundToDouble() ? 0 : 1)}%'),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: (res.percentSum - 100).abs() < .05 ? Z.win : Z.danger,
              fontFeatures: Z.tabular,
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final p in prizePresets) _preset(_presetName(p), p),
              _preset(S.t.presetEven(c.percents.length), flatPercents(c.percents.length)),
              _preset(S.t.presetStepped(c.percents.length), steppedPercents(c.percents.length)),
            ],
          ),
        ),
        if ((res.percentSum - 100).abs() >= .05)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    res.percentSum > 100 ? S.t.over100 : S.t.leftUnsplit((100 - res.percentSum).toStringAsFixed(1)),
                    style: TextStyle(color: Z.danger, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    c.percents = normalisePercents(c.percents);
                    _changed();
                  },
                  child: Text(S.t.balance),
                ),
              ],
            ),
          ),
        SizedBox(height: 10),

        // ---- table
        Card(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(14, 6, 14, 6),
                  child: Row(
                    children: [
                      SizedBox(width: 44, child: Text(S.t.colPlace, style: _head)),
                      Expanded(child: Text(S.t.colPlayer, style: _head)),
                      SizedBox(
                        width: 98,
                        child: Text(S.t.colPercent, textAlign: TextAlign.center, style: _head),
                      ),
                      SizedBox(
                        width: 74,
                        child: Text(S.t.colAmount, textAlign: TextAlign.end, style: _head),
                      ),
                    ],
                  ),
                ),
                for (final l in res.lines) _line(l, t),
                Padding(
                  padding: EdgeInsets.fromLTRB(8, 4, 8, 4),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          c.percents = [...c.percents, 0];
                          _changed();
                        },
                        icon: Icon(Icons.add, size: 18),
                        label: Text(S.t.place),
                      ),
                      if (c.percents.length > 1)
                        TextButton.icon(
                          onPressed: () {
                            c.percents = c.percents.sublist(0, c.percents.length - 1);
                            _changed();
                          },
                          icon: Icon(Icons.remove, size: 18),
                          label: Text(S.t.place),
                        ),
                      Spacer(),
                      if (res.leftover > 0)
                        Text(S.t.notHandedOut(money(res.leftover)), style: TextStyle(color: Z.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 10),
        Text(
          t == null
              ? S.t.standaloneNote
              : official
              ? S.t.finalNote
              : S.t.liveNote,
          style: TextStyle(color: Z.muted, fontSize: 12.5),
        ),
        SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => copyText(context, _text(res, t), S.t.prizesWhat),
          icon: Icon(Icons.copy_rounded),
          label: Text(S.t.copyPrizes),
        ),
      ],
    );
  }

  Widget _preset(String name, List<double> pcts) {
    return Padding(
      padding: EdgeInsetsDirectional.only(end: 8),
      child: ActionChip(
        label: Text(name),
        onPressed: () {
          c.percents = [...pcts];
          _changed();
        },
      ),
    );
  }

  Widget _line(PrizeLine l, Tournament? t) {
    final idx = l.place - 1;
    final configured = idx < c.percents.length;
    final shared = configured && (l.percent - c.percents[idx]).abs() > 1e-6;
    return Container(
      padding: EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              l.label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: l.place <= 3 ? Z.accent : Z.text,
                fontFeatures: Z.tabular,
              ),
            ),
          ),
          Expanded(
            child: Text(
              l.playerId == null ? '—' : t!.nameOf(l.playerId),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w600, color: l.playerId == null ? Z.muted : Z.text),
            ),
          ),
          SizedBox(
            width: 98,
            child: configured
                ? _PctField(
                    key: ValueKey('pct$idx'),
                    value: c.percents[idx],
                    hint: shared ? '→ ${_fmtPct(l.percent)}' : null,
                    onChanged: (v) {
                      c.percents[idx] = v;
                      _changed();
                    },
                  )
                : Text(
                    '→ ${_fmtPct(l.percent)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Z.muted, fontSize: 13, fontFeatures: Z.tabular),
                  ),
          ),
          SizedBox(
            width: 74,
            child: Text(
              money(l.amount),
              textAlign: TextAlign.end,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, fontFeatures: Z.tabular),
            ),
          ),
        ],
      ),
    );
  }

  static TextStyle get _head => TextStyle(fontSize: 12, color: Z.muted, fontWeight: FontWeight.w600);

  String _fmtPct(double v) => '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}%';

  String _text(PrizeResult res, Tournament? t) {
    final b = StringBuffer('${t == null ? S.t.prizeSplitHeader : S.t.prizesHeader(t.name)}\n');
    b.writeln(S.t.poolLine(money(res.net)));
    for (final l in res.lines) {
      if (l.amount <= 0) continue;
      final who = l.playerId == null ? '' : ' ${t!.nameOf(l.playerId)}';
      b.writeln('${l.label}.$who — ${money(l.amount)}');
    }
    return b.toString();
  }
}

class _NumField extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  const _NumField({super.key, required this.label, required this.value, required this.onChanged});

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    final v = widget.value;
    _c = TextEditingController(text: v == 0 ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v'));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, fontFeatures: Z.tabular),
      decoration: InputDecoration(labelText: widget.label, hintText: '0'),
      onChanged: (s) => widget.onChanged(double.tryParse(s) ?? 0),
    );
  }
}

class _PctField extends StatefulWidget {
  final double value;
  final String? hint;
  final ValueChanged<double> onChanged;
  const _PctField({super.key, required this.value, required this.onChanged, this.hint});

  @override
  State<_PctField> createState() => _PctFieldState();
}

class _PctFieldState extends State<_PctField> {
  late final TextEditingController _c;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    final v = widget.value;
    _c = TextEditingController(text: v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v');
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  @override
  void didUpdateWidget(covariant _PctField old) {
    super.didUpdateWidget(old);
    // Presets / balancing change the value from outside: show it unless the
    // user is typing in this field.
    if (!_focus.hasFocus && (double.tryParse(_c.text) ?? 0) != widget.value) _c.text = _fmt(widget.value);
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 38,
          width: 72,
          // LTR so the % sign sits after the number.
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _c,
              focusNode: _focus,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: Z.tabular),
              decoration: const InputDecoration(suffixText: '%', contentPadding: EdgeInsets.symmetric(horizontal: 8)),
              onChanged: (s) => widget.onChanged(double.tryParse(s) ?? 0),
            ),
          ),
        ),
        if (widget.hint != null)
          Text(
            widget.hint!,
            style: TextStyle(fontSize: 11, color: Z.muted, fontFeatures: Z.tabular),
          ),
      ],
    );
  }
}

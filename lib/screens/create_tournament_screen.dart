import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// New tournament: name, format, players and the main settings. Rounds and
/// top cut follow the recommended values for the player count until the
/// organiser changes them by hand.
class CreateTournamentScreen extends StatefulWidget {
  const CreateTournamentScreen({super.key});

  @override
  State<CreateTournamentScreen> createState() => _CreateTournamentScreenState();
}

class _CreateTournamentScreenState extends State<CreateTournamentScreen> {
  late final TextEditingController _name;
  final _players = TextEditingController();
  TFormat _format = TFormat.swiss;
  int _rounds = 3;
  bool _roundsTouched = false;
  int _top = 0; // default: no top cut
  int _swissBo = 3;
  int _topBo = 3;
  bool _third = false;
  int _minutes = 45;
  int _overtime = 5;

  @override
  void initState() {
    super.initState();
    final d = DateTime.now();
    _name = TextEditingController(text: S.t.defaultTournamentName(d.day, d.month));
    _players.addListener(_sync);
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _players.dispose();
    super.dispose();
  }

  List<String> get _names =>
      _players.text.split(RegExp(r'[\n,]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  void _sync() {
    final n = _names.length;
    setState(() {
      if (!_roundsTouched) _rounds = recommendedSwissRounds(n);
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = _names.length;
    final rr = _format == TFormat.roundRobin;
    return Scaffold(
      appBar: AppBar(title: Text(S.t.newTournament)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          TextField(
            controller: _name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            decoration: InputDecoration(labelText: S.t.tournamentName),
          ),
          SectionTitle(S.t.format),
          SegmentedButton<TFormat>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: TFormat.swiss, label: Text(S.t.swiss)),
              ButtonSegment(value: TFormat.roundRobin, label: Text(S.t.roundRobin)),
            ],
            selected: {_format},
            onSelectionChanged: (s) => setState(() => _format = s.first),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              rr ? S.t.rrExplain : S.t.swissExplain,
              style: const TextStyle(color: Z.muted, fontSize: 13, height: 1.4),
            ),
          ),
          SectionTitle(S.t.playersTitle, trailing: Pill('$n', color: n >= 2 ? Z.gold : Z.muted)),
          TextField(
            controller: _players,
            minLines: 5,
            maxLines: 12,
            decoration: InputDecoration(hintText: S.t.playersHint),
          ),
          SectionTitle(S.t.settings),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(children: [
                if (!rr)
                  SettingRow(
                    title: S.t.swissRounds,
                    subtitle: S.t.recommendedFor(n, recommendedSwissRounds(n)),
                    child: Stepper2(
                        value: _rounds,
                        min: 1,
                        max: 15,
                        onChanged: (v) => setState(() {
                              _rounds = v;
                              _roundsTouched = true;
                            })),
                  )
                else
                  SettingRow(
                    title: S.t.rounds,
                    subtitle: S.t.setByPlayers,
                    child: Text('${rrRoundCount(n)}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, fontFeatures: Z.tabular)),
                  ),
                const Divider(),
                SettingRow(
                  title: S.t.topCut,
                  subtitle: recommendedTopCut(n) > 0 ? S.t.topCutUsual(n, recommendedTopCut(n)) : S.t.topCutExplain,
                  child: DropdownButton<int>(
                    value: _top,
                    underline: const SizedBox(),
                    borderRadius: BorderRadius.circular(12),
                    items: [0, 2, 4, 8, 16, 32]
                        .map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? S.t.none : S.t.top(v))))
                        .toList(),
                    onChanged: (v) => setState(() => _top = v!),
                  ),
                ),
                const Divider(),
                SettingRow(
                  title: S.t.gamesPerRound,
                  child: _boPicker(_swissBo, (v) => setState(() => _swissBo = v)),
                ),
                if (_top > 0) ...[
                  const Divider(),
                  SettingRow(title: S.t.gamesPerTop, child: _boPicker(_topBo, (v) => setState(() => _topBo = v))),
                  const Divider(),
                  SettingRow(
                    title: S.t.thirdPlaceMatch,
                    child: Switch(value: _third, onChanged: (v) => setState(() => _third = v)),
                  ),
                ],
                const Divider(),
                SettingRow(
                  title: S.t.roundTime,
                  child: Stepper2(
                      value: _minutes,
                      min: 5,
                      max: 120,
                      format: (v) => '$v′',
                      onChanged: (v) => setState(() => _minutes = v)),
                ),
                const Divider(),
                SettingRow(
                  title: S.t.overtime,
                  subtitle: S.t.overtimeExplain,
                  child: Stepper2(
                      value: _overtime,
                      max: 30,
                      format: (v) => '$v′',
                      onChanged: (v) => setState(() => _overtime = v)),
                ),
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _name.text.trim().isEmpty ? null : _create,
            child: Text(n < 2 ? S.t.openAndGetCode : S.t.createWith(n)),
          ),
        ),
      ),
    );
  }

  Widget _boPicker(int v, ValueChanged<int> on) => SegmentedButton<int>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(value: 1, label: Text('BO1')),
          ButtonSegment(value: 3, label: Text('BO3')),
        ],
        selected: {v},
        onSelectionChanged: (s) => on(s.first),
      );

  void _create() {
    final t = Tournament(
      name: _name.text.trim(),
      format: _format,
      swissRounds: _rounds,
      autoRounds: !_roundsTouched,
      topCut: _top,
      swissBestOf: _swissBo,
      topBestOf: _topBo,
      thirdPlace: _third,
      roundMinutes: _minutes,
      overtimeMinutes: _overtime,
    );
    final seen = <String>{};
    for (final name in _names) {
      var nm = name;
      var k = 2;
      while (!seen.add(nm)) {
        nm = '$name ${k++}';
      }
      t.players.add(Player(id: newId(), name: nm));
    }
    Navigator.pop(context, t);
  }
}

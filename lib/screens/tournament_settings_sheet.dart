import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/models.dart';
import '../l10n.dart';
import '../state/app_state.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Settings that may change mid-event. Things that would break what was
/// already played (format, fewer rounds than played) are locked.
class TournamentSettingsSheet extends StatefulWidget {
  final Tournament t;
  const TournamentSettingsSheet({super.key, required this.t});

  @override
  State<TournamentSettingsSheet> createState() => _TournamentSettingsSheetState();
}

class _TournamentSettingsSheetState extends State<TournamentSettingsSheet> {
  Tournament get t => widget.t;

  void _set(VoidCallback f) {
    setState(f);
    context.read<AppState>().changed();
  }

  @override
  Widget build(BuildContext context) {
    final played = t.swissRoundsList.length;
    final topStarted = t.topRoundsList.isNotEmpty;
    // A finished event's standings and prizes are final: no structural changes.
    final locked = topStarted || t.finished;
    final rr = t.format == TFormat.roundRobin;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(S.t.tournamentSettings, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (hostSyncOf(context, listen: false) != null)
            SettingRow(
              title: S.t.joinModeLabel,
              child: DropdownButton<String>(
                value: t.joinMode,
                onChanged: (v) => _set(() => t.joinMode = v ?? 'open'),
                items: [
                  DropdownMenuItem(value: 'open', child: Text(S.t.joinOpen)),
                  DropdownMenuItem(value: 'approval', child: Text(S.t.joinApproval)),
                  DropdownMenuItem(value: 'closedOnStart', child: Text(S.t.joinClosedOnStart)),
                ],
              ),
            ),
          SettingRow(
            title: S.t.name,
            child: TextButton.icon(
              icon: const Icon(Icons.edit, size: 18),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              onPressed: () async {
                final v = await promptText(context, S.t.tournamentName, initial: t.name);
                if (v != null && v.isNotEmpty) _set(() => t.name = v);
              },
            ),
          ),
          const Divider(),
          if (!rr)
            SettingRow(
              title: S.t.swissRounds,
              subtitle: S.t.recommendedPlayed(recommendedSwissRounds(t.players.length), played),
              child: Stepper2(
                value: t.swissRounds,
                min: played < 1 ? 1 : played,
                max: 15,
                onChanged: locked ? null : (v) => _set(() => t.swissRounds = v),
              ),
            )
          else
            SettingRow(title: S.t.roundRobin, subtitle: S.t.rrRoundsBySchedule, child: Text('${t.plannedSwissRounds}')),
          const Divider(),
          SettingRow(
            title: S.t.topCut,
            subtitle: topStarted ? S.t.topAlreadyStarted : (t.finished ? S.t.tournamentFinishedLocked : null),
            child: DropdownButton<int>(
              value: t.topCut,
              underline: const SizedBox(),
              items: [0, 2, 4, 8, 16, 32]
                  .map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? S.t.none : S.t.top(v))))
                  .toList(),
              onChanged: locked ? null : (v) => _set(() => t.topCut = v!),
            ),
          ),
          const Divider(),
          SettingRow(title: S.t.gamesPerRound, child: _bo(t.swissBestOf, (v) => _set(() => t.swissBestOf = v))),
          const Divider(),
          SettingRow(title: S.t.gamesPerTop, child: _bo(t.topBestOf, (v) => _set(() => t.topBestOf = v))),
          const Divider(),
          SettingRow(
            title: S.t.thirdPlaceMatch,
            child: Switch(value: t.thirdPlace, onChanged: (v) => _set(() => t.thirdPlace = v)),
          ),
          const Divider(),
          SettingRow(
            title: S.t.roundTime,
            child: Stepper2(
                value: t.roundMinutes,
                min: 5,
                max: 120,
                format: (v) => '$v′',
                onChanged: (v) => _set(() => t.roundMinutes = v)),
          ),
          const Divider(),
          SettingRow(
            title: S.t.overtime,
            subtitle: S.t.overtimeExplain,
            child: Stepper2(
                value: t.overtimeMinutes,
                max: 30,
                format: (v) => '$v′',
                onChanged: (v) => _set(() => t.overtimeMinutes = v)),
          ),
          const Divider(),
          SettingRow(
            title: S.t.omwFloor,
            subtitle: S.t.omwFloorExplain,
            child: Stepper2(
              value: (t.omwFloor * 100).round(),
              min: 0,
              max: 50,
              format: (v) => '$v%',
              onChanged: (v) => _set(() => t.omwFloor = v / 100),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            S.t.tiebreakExplain,
            style: const TextStyle(color: Z.muted, fontSize: 12.5, height: 1.5),
          ),
        ]),
      ),
    );
  }

  Widget _bo(int v, ValueChanged<int> on) => SegmentedButton<int>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [ButtonSegment(value: 1, label: Text('BO1')), ButtonSegment(value: 3, label: Text('BO3'))],
        selected: {v},
        onSelectionChanged: (s) => on(s.first),
      );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/models.dart';
import '../state/app_state.dart';
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
    final rr = t.format == TFormat.roundRobin;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('הגדרות טורניר', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          SettingRow(
            title: 'שם',
            child: TextButton.icon(
              icon: const Icon(Icons.edit, size: 18),
              label: Text(t.name),
              onPressed: () async {
                final v = await promptText(context, 'שם הטורניר', initial: t.name);
                if (v != null && v.isNotEmpty) _set(() => t.name = v);
              },
            ),
          ),
          const Divider(),
          if (!rr)
            SettingRow(
              title: 'סיבובי סוויס',
              subtitle: 'מומלץ: ${recommendedSwissRounds(t.players.length)}${played > 0 ? ' · שוחקו $played' : ''}',
              child: Stepper2(
                value: t.swissRounds,
                min: played < 1 ? 1 : played,
                max: 15,
                onChanged: topStarted ? (_) {} : (v) => _set(() => t.swissRounds = v),
              ),
            )
          else
            SettingRow(title: 'ראונד רובין', subtitle: 'מספר הסיבובים נקבע לפי השחקנים', child: Text('${t.plannedSwissRounds}')),
          const Divider(),
          SettingRow(
            title: 'טופ קאט',
            subtitle: topStarted ? 'הטופ כבר התחיל' : null,
            child: DropdownButton<int>(
              value: t.topCut,
              underline: const SizedBox(),
              items: [0, 2, 4, 8, 16, 32]
                  .map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? 'בלי' : 'טופ $v')))
                  .toList(),
              onChanged: topStarted ? null : (v) => _set(() => t.topCut = v!),
            ),
          ),
          const Divider(),
          SettingRow(title: 'משחקים בסיבוב', child: _bo(t.swissBestOf, (v) => _set(() => t.swissBestOf = v))),
          const Divider(),
          SettingRow(title: 'משחקים בטופ קאט', child: _bo(t.topBestOf, (v) => _set(() => t.topBestOf = v))),
          const Divider(),
          SettingRow(
            title: 'משחק על המקום השלישי',
            child: Switch(value: t.thirdPlace, onChanged: (v) => _set(() => t.thirdPlace = v)),
          ),
          const Divider(),
          SettingRow(
            title: 'זמן סיבוב',
            child: Stepper2(
                value: t.roundMinutes,
                min: 5,
                max: 120,
                format: (v) => '$v′',
                onChanged: (v) => _set(() => t.roundMinutes = v)),
          ),
          const Divider(),
          SettingRow(
            title: 'רצפה ל-OMW%',
            subtitle: 'אחוז הנצחונות המינימלי שנספר ליריב חלש בחישוב שובר השוויון. ברירת מחדל 33%.',
            child: Stepper2(
              value: (t.omwFloor * 100).round(),
              min: 0,
              max: 50,
              format: (v) => '$v%',
              onChanged: (v) => _set(() => t.omwFloor = v / 100),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'שוברי שוויון לפי סדר: נקודות ← OMW% (ממוצע אחוזי הנצחון של היריבים) ← OOMW% (ממוצע ה-OMW של היריבים) ← הגרלה. נצחון 3, תיקו 1, הפסד והפסד כפול 0, BYE נחשב נצחון.',
            style: TextStyle(color: Z.muted, fontSize: 12.5, height: 1.5),
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

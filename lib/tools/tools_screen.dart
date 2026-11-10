import 'package:flutter/material.dart';

import '../screens/tabs/prizes_tab.dart';
import '../theme.dart';
import 'coin_screen.dart';
import 'dice_screen.dart';
import 'memory_screen.dart';
import 'rps_screen.dart';
import 'rules_screen.dart';
import 'tool_icons.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    return Scaffold(
      appBar: AppBar(title: const Text('כלי משחק')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // The memory gauge is the one used every game: give it the full row.
          _ToolTile(
            title: 'מד זיכרון',
            body: 'Memory gauge לדיג׳ימון: מעביר תור לבד כשהזיכרון עובר לצד של היריב.',
            icon: const GaugeIcon(),
            color: Z.blue,
            tall: true,
            onTap: () => open(const MemoryScreen()),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _ToolTile(
                title: 'קוביות',
                body: 'כולל "מי מתחיל"',
                icon: const DieIcon(),
                color: Z.gold,
                onTap: () => open(const DiceScreen()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ToolTile(
                title: 'מטבע',
                body: 'עץ או פלי',
                icon: const CoinIcon(),
                color: Z.gold,
                onTap: () => open(const CoinScreen()),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _ToolTile(
                title: 'אבן נייר ומספריים',
                body: 'שני שחקנים או נגד הטלפון',
                icon: const Text('✌️', style: TextStyle(fontSize: 34)),
                color: Z.coral,
                onTap: () => open(const RpsScreen()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ToolTile(
                title: 'מחשבון פרסים',
                body: 'בלי טורניר',
                icon: const Icon(Icons.payments_outlined, size: 38, color: Z.win),
                color: Z.win,
                onTap: () => open(Scaffold(appBar: AppBar(title: const Text('מחשבון פרסים')), body: const PrizesTab())),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _ToolTile(
            title: 'חוקי דיג׳ימון',
            body: 'חוברת החוקים, Comprehensive Rules, מילון מונחים ורשימת הקלפים האסורים.',
            icon: const Icon(Icons.menu_book_rounded, size: 40, color: Z.blue),
            color: Z.blue,
            tall: true,
            onTap: () => open(const RulesScreen()),
          ),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  final String title;
  final String body;
  final Widget icon;
  final Color color;
  final bool tall;
  final VoidCallback onTap;

  const _ToolTile(
      {required this.title, required this.body, required this.icon, required this.color, required this.onTap, this.tall = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Z.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: tall ? 132 : 150,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: .28)),
          ),
          child: tall
              ? Row(children: [
                  SizedBox(width: 64, child: Center(child: icon)),
                  const SizedBox(width: 14),
                  Expanded(child: _texts()),
                  Icon(Icons.chevron_left, color: color),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(height: 48, child: Align(alignment: AlignmentDirectional.centerStart, child: icon)),
                  const Spacer(),
                  _texts(),
                ]),
        ),
      ),
    );
  }

  Widget _texts() => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(body, style: const TextStyle(fontSize: 12.5, color: Z.muted, height: 1.35)),
      ]);
}

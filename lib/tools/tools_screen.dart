import 'package:flutter/material.dart';

import '../l10n.dart';
import '../screens/tabs/prizes_tab.dart';
import '../theme.dart';
import '../widgets/common.dart';
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
      appBar: AppBar(title: Text(S.t.gameTools), actions: const [LangButton()]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // The memory gauge is the one used every game: give it the full row.
          _ToolTile(
            title: S.t.memoryGauge,
            body: S.t.memoryGaugeBody,
            icon: const GaugeIcon(),
            color: Z.blue,
            tall: true,
            onTap: () => open(const MemoryScreen()),
          ),
          const SizedBox(height: 12),
          // Equal-height pair; grows when a longer language needs more lines.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ToolTile(
                    title: S.t.dice,
                    body: S.t.diceBody,
                    icon: const DieIcon(),
                    color: Z.gold,
                    onTap: () => open(const DiceScreen()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ToolTile(
                    title: S.t.coin,
                    body: S.t.coinBody,
                    icon: const CoinIcon(),
                    color: Z.gold,
                    onTap: () => open(const CoinScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Equal-height pair; grows when a longer language needs more lines.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ToolTile(
                    title: S.t.rps,
                    body: S.t.rpsBody,
                    icon: const Text('✌️', style: TextStyle(fontSize: 34)),
                    color: Z.coral,
                    onTap: () => open(const RpsScreen()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ToolTile(
                    title: S.t.prizeCalculator,
                    body: S.t.prizeCalculatorBody,
                    icon: const Icon(Icons.payments_outlined, size: 38, color: Z.win),
                    color: Z.win,
                    onTap: () => open(
                      Scaffold(
                        appBar: AppBar(title: Text(S.t.prizeCalculator)),
                        body: const PrizesTab(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ToolTile(
            title: S.t.digimonRules,
            body: S.t.digimonRulesBody,
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

  const _ToolTile({
    required this.title,
    required this.body,
    required this.icon,
    required this.color,
    required this.onTap,
    this.tall = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Z.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: tall ? 132 : 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: .28)),
          ),
          child: tall
              ? Row(
                  children: [
                    SizedBox(width: 64, child: Center(child: icon)),
                    const SizedBox(width: 14),
                    Expanded(child: _texts()),
                    Icon(Icons.chevron_right, color: color),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SizedBox(
                      height: 48,
                      child: Align(alignment: AlignmentDirectional.centerStart, child: icon),
                    ),
                    const SizedBox(height: 10),
                    _texts(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _texts() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 3),
      Text(body, style: const TextStyle(fontSize: 12.5, color: Z.muted, height: 1.35)),
    ],
  );
}

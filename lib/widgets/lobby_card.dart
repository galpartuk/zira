import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../l10n.dart';
import '../theme.dart';

/// What a player sees while nothing is asked of them: "you're in", who else
/// joined so far, and a pulse that shows the screen is live, not stuck.
class LobbyCard extends StatelessWidget {
  final Tournament t;

  /// The signed-in player's uid (their chip is highlighted).
  final String uid;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  /// List who joined (before the first round); later only the count matters.
  final bool showPlayers;

  const LobbyCard({
    super.key,
    required this.t,
    required this.uid,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.showPlayers = true,
  });

  @override
  Widget build(BuildContext context) {
    final players = t.activePlayers;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Pulse(color: color, icon: icon),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14.5, color: Z.muted, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 2),
                const WaitingDots(),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.groups_rounded, color: Z.blue, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    S.t.playersIn(players.length),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                const LiveBadge(),
              ],
            ),
            if (showPlayers && players.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in players)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: p.uid == uid ? Z.blue.withValues(alpha: .2) : Z.raised,
                        border: Border.all(color: p.uid == uid ? Z.blue : Z.line),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        p.name,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: p.uid == uid ? FontWeight.w700 : FontWeight.w600,
                          color: p.uid == uid ? Z.blue : Z.text,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Repeating animations run only when this is true. Widget tests switch it
/// off: an endless animation never lets `pumpAndSettle` finish.
bool lobbyAnimations = true;

mixin _Loop<T extends StatefulWidget> on State<T>, SingleTickerProviderStateMixin<T> {
  late final AnimationController loop;
  Duration get period;

  @override
  void initState() {
    super.initState();
    loop = AnimationController(vsync: this, duration: period);
    if (lobbyAnimations) loop.repeat();
  }

  @override
  void dispose() {
    loop.dispose();
    super.dispose();
  }
}

/// An icon in a disc with rings rippling out of it.
class Pulse extends StatefulWidget {
  final Color color;
  final IconData icon;
  const Pulse({super.key, required this.color, required this.icon});

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin, _Loop {
  @override
  Duration get period => const Duration(milliseconds: 2200);

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return SizedBox(
      width: 112,
      height: 112,
      child: AnimatedBuilder(
        animation: loop,
        builder: (_, child) => Stack(
          alignment: Alignment.center,
          children: [
            for (final shift in const [0.0, .5])
              Builder(
                builder: (_) {
                  final v = (loop.value + shift) % 1;
                  return Container(
                    width: 64 + 48 * v,
                    height: 64 + 48 * v,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: c.withValues(alpha: .55 * (1 - v)), width: 2),
                    ),
                  );
                },
              ),
            child!,
          ],
        ),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.withValues(alpha: .18),
            border: Border.all(color: c),
          ),
          child: Icon(widget.icon, color: c, size: 34),
        ),
      ),
    );
  }
}

/// Three dots lighting up in turn, after a "waiting…" line.
class WaitingDots extends StatefulWidget {
  const WaitingDots({super.key});

  @override
  State<WaitingDots> createState() => _WaitingDotsState();
}

class _WaitingDotsState extends State<WaitingDots> with SingleTickerProviderStateMixin, _Loop {
  @override
  Duration get period => const Duration(milliseconds: 1200);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: loop,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Z.muted.withValues(alpha: (loop.value * 3).floor() % 3 == i ? 1 : .3),
              ),
            ),
        ],
      ),
    );
  }
}

/// A blinking green dot + "Live": the screen updates by itself.
class LiveBadge extends StatefulWidget {
  const LiveBadge({super.key});

  @override
  State<LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<LiveBadge> with SingleTickerProviderStateMixin, _Loop {
  @override
  Duration get period => const Duration(milliseconds: 1600);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: loop,
          builder: (_, _) {
            final v = loop.value < .5 ? loop.value * 2 : (1 - loop.value) * 2; // 0 → 1 → 0
            return Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Z.win.withValues(alpha: 1 - .7 * v),
              ),
            );
          },
        ),
        const SizedBox(width: 6),
        Text(
          S.t.live,
          style: TextStyle(fontSize: 12.5, color: Z.win, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

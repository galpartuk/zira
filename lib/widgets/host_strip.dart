import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../l10n.dart';
import '../state/host_sync.dart';
import '../theme.dart';
import 'common.dart';

class HostStrip extends StatelessWidget {
  final Tournament t;
  final HostSync sync;
  const HostStrip({super.key, required this.t, required this.sync});

  @override
  Widget build(BuildContext context) {
    final c = sync.roundCounts(t);
    return Container(
      color: Z.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.t.joinCodeLabel, style: TextStyle(fontSize: 12, color: Z.muted)),
                Text(
                  t.joinCode ?? '——————',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                    fontFeatures: Z.tabular,
                  ),
                ),
                if (c.total > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Pill(S.t.countReported(c.reported, c.total), color: c.reported == c.total ? Z.win : Z.muted),
                        if (c.pending > 0) Pill(S.t.countPending(c.pending), color: Z.amber),
                        if (c.disputed > 0) Pill(S.t.countDisputed(c.disputed), color: Z.danger),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (t.joinCode == null)
            TextButton(onPressed: () => sync.ensureJoinCode(t), child: Text(S.t.getCode))
          else
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () => copyText(context, S.t.shareCodeText(t.name, t.joinCode!), S.t.joinCodeLabel),
            ),
        ],
      ),
    );
  }
}

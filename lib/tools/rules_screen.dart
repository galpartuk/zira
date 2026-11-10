import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Official Digimon Card Game rules documents (English site). The PDF links
/// have no version suffix, so they always open the current edition.
class RuleLink {
  final String title;
  final String body;
  final String url;
  final IconData icon;
  const RuleLink(this.title, this.body, this.url, this.icon);
}

List<RuleLink> get digimonRuleLinks => [
      RuleLink(S.t.ruleManual, S.t.ruleManualBody, 'https://en.digimoncard.com/rule/pdf/manual.pdf', Icons.menu_book_rounded),
      RuleLink(S.t.comprehensive, S.t.comprehensiveBody, 'https://en.digimoncard.com/rule/pdf/general_rule.pdf',
          Icons.gavel_rounded),
      RuleLink(S.t.glossary, S.t.glossaryBody, 'https://en.digimoncard.com/rule/pdf/glossary.pdf', Icons.translate_rounded),
      RuleLink(S.t.banned, S.t.bannedBody, 'https://en.digimoncard.com/rule/restriction_card/', Icons.block_rounded),
      RuleLink(S.t.ruleChanges, S.t.ruleChangesBody, 'https://en.digimoncard.com/rule/rule_change/', Icons.update_rounded),
      RuleLink(S.t.floorRules, S.t.floorRulesBody, 'https://dcd.sc/bcg10', Icons.groups_rounded),
      RuleLink(S.t.allRules, S.t.allRulesBody, 'https://en.digimoncard.com/rule/', Icons.public_rounded),
    ];

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) toast(context, S.t.cantOpenLink);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t.digimonRules)),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: digimonRuleLinks.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (c, i) {
          if (i == digimonRuleLinks.length) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(S.t.rulesFooter, style: const TextStyle(color: Z.muted, fontSize: 12.5, height: 1.45)),
            );
          }
          final l = digimonRuleLinks[i];
          final pdf = l.url.endsWith('.pdf');
          return Material(
            color: Z.surface,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _open(context, l.url),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                child: Row(children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: Z.blue.withValues(alpha: .14), borderRadius: BorderRadius.circular(11)),
                    child: Icon(l.icon, color: Z.blue),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(l.body, style: const TextStyle(fontSize: 13, color: Z.muted, height: 1.35)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  if (pdf) const Pill('PDF', color: Z.muted),
                  const Icon(Icons.open_in_new_rounded, size: 18, color: Z.muted),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

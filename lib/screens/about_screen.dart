import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import '../theme.dart';
import '../version.dart';
import '../widgets/common.dart';

/// Who made the app, how to reach them, and what it is built with.
///
/// The developer card is always in English (it is a professional profile);
/// the rest of the page follows the app language.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const email = 'galpartuk007@gmail.com';
  static const linkedIn = 'https://www.linkedin.com/in/partuk-gal';
  static const gitHub = 'https://github.com/galpartuk';
  static const source = 'https://github.com/galpartuk/zira';
  static const stack = [
    'Flutter',
    'Dart',
    'Firebase Auth',
    'Cloud Firestore',
    'Security rules',
    'Provider',
    '160+ tests',
  ];

  Future<void> _open(BuildContext context, Uri url) async {
    var ok = false;
    try {
      ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && context.mounted) toast(context, S.t.cantOpenLink);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t.about)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _app(),
              const SizedBox(height: 16),
              Directionality(textDirection: TextDirection.ltr, child: _developer(context)),
              const SizedBox(height: 24),
              SectionTitle(S.t.builtWith),
              const SizedBox(height: 8),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Wrap(spacing: 8, runSpacing: 8, children: [for (final s in stack) _chip(s)]),
              ),
              const SizedBox(height: 12),
              _link(
                context,
                Icons.code_rounded,
                S.t.sourceCode,
                'github.com/galpartuk/zira',
                Uri.parse(source),
                key: const ValueKey('about-source'),
              ),
              const SizedBox(height: 24),
              Text(S.t.fanMadeNotice, style: const TextStyle(color: Z.muted, fontSize: 12.5, height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _app() => Row(
    children: [
      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Z.gold.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Z.gold.withValues(alpha: .5)),
        ),
        child: const Icon(Icons.emoji_events_rounded, color: Z.gold, size: 28),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.t.appName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text(
              '${S.t.aboutTagline} · ${S.t.versionLabel(appVersion)}',
              style: const TextStyle(color: Z.muted, fontSize: 13.5),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _developer(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Z.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Z.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DESIGNED & BUILT BY',
          style: TextStyle(color: Z.muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.4),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Z.gold, width: 2),
              ),
              child: const Text(
                'GP',
                style: TextStyle(color: Z.gold, fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gal Partuk', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.15)),
                  Text('Full Stack Developer', style: TextStyle(color: Z.muted, fontSize: 14.5)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Z.win.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Z.win.withValues(alpha: .55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(color: Z.win, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              const Text(
                'Open to work',
                style: TextStyle(color: Z.win, fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'I designed and built Duel Network end to end: the pairing and standings engine, '
          'live online tournaments, and the Android and web apps.\n\n'
          'I am looking for a full-stack role, hybrid or on-site in Central Israel.',
          style: TextStyle(fontSize: 14.5, height: 1.55),
        ),
        const SizedBox(height: 16),
        _link(
          context,
          Icons.mail_outline_rounded,
          'Email',
          email,
          Uri(scheme: 'mailto', path: email),
          key: const ValueKey('about-email'),
        ),
        const SizedBox(height: 8),
        _link(
          context,
          Icons.work_outline_rounded,
          'LinkedIn',
          'linkedin.com/in/partuk-gal',
          Uri.parse(linkedIn),
          key: const ValueKey('about-linkedin'),
        ),
        const SizedBox(height: 8),
        _link(
          context,
          Icons.terminal_rounded,
          'GitHub',
          'github.com/galpartuk',
          Uri.parse(gitHub),
          key: const ValueKey('about-github'),
        ),
      ],
    ),
  );

  Widget _link(BuildContext context, IconData icon, String title, String value, Uri url, {Key? key}) => Material(
    key: key,
    color: Z.raised,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(context, url),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(icon, color: Z.gold, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Z.muted, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.open_in_new_rounded, color: Z.muted, size: 17),
          ],
        ),
      ),
    ),
  );

  Widget _chip(String s) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: Z.raised,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Z.line),
    ),
    child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
  );
}

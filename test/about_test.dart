// The About / credits page.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zira/l10n.dart';
import 'package:zira/screens/about_screen.dart';
import 'package:zira/theme.dart';
import 'package:zira/tools/tools_screen.dart';
import 'package:zira/version.dart';

void main() {
  test('the version on the About page is the one in pubspec.yaml', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(line.split(':')[1].trim().split('+').first, appVersion);
  });

  for (final code in ['en', 'he']) {
    testWidgets('About opens from the tools tab and fits a small phone ($code)', (tester) async {
      Lang.instance.code = code;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Directionality(
            textDirection: code == 'he' ? TextDirection.rtl : TextDirection.ltr,
            child: const ToolsScreen(),
          ),
        ),
      );
      await tester.tap(find.byTooltip(S.t.about));
      await tester.pumpAndSettle();
      expect(find.byType(AboutScreen), findsOneWidget);
      expect(find.text('Gal Partuk'), findsOneWidget);
      expect(find.text('Open to work'), findsOneWidget);
      expect(find.textContaining(appVersion), findsOneWidget);
      for (final k in ['about-email', 'about-linkedin', 'about-github']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget);
      }
      expect(tester.takeException(), isNull); // no overflow
      Lang.instance.code = 'en';
    });
  }
}

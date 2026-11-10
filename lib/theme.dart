import 'package:flutter/material.dart';

/// Colour tokens. Player A / B colours are used everywhere a "side" exists:
/// match cards, the memory gauge, rock-paper-scissors.
class Z {
  static const ink = Color(0xFF10202F); // background
  static const surface = Color(0xFF172B3E); // cards
  static const raised = Color(0xFF1F3851); // inputs, chips
  static const line = Color(0xFF2B4762); // borders
  static const text = Color(0xFFEAF0F7);
  static const muted = Color(0xFF8FA6BD);
  static const gold = Color(0xFFF2C14E); // primary action / judge
  static const blue = Color(0xFF4CC3E8); // player A / bottom
  static const coral = Color(0xFFF27C5C); // player B / top
  static const win = Color(0xFF5BD08A);
  static const danger = Color(0xFFE5534B);

  static const tabular = [FontFeature.tabularFigures()];
}

ThemeData buildTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Z.gold,
    onPrimary: Color(0xFF2A1F00),
    secondary: Z.blue,
    onSecondary: Color(0xFF00222E),
    tertiary: Z.coral,
    onTertiary: Color(0xFF330E04),
    error: Z.danger,
    onError: Colors.white,
    surface: Z.ink,
    onSurface: Z.text,
    surfaceContainerLowest: Z.ink,
    surfaceContainerLow: Z.surface,
    surfaceContainer: Z.surface,
    surfaceContainerHigh: Z.raised,
    surfaceContainerHighest: Z.raised,
    onSurfaceVariant: Z.muted,
    outline: Z.line,
    outlineVariant: Z.line,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Heebo');
  return base.copyWith(
    scaffoldBackgroundColor: Z.ink,
    textTheme: base.textTheme.apply(bodyColor: Z.text, displayColor: Z.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: Z.ink,
      foregroundColor: Z.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Heebo', fontSize: 21, fontWeight: FontWeight.w800, color: Z.text),
    ),
    cardTheme: const CardThemeData(
      color: Z.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
    ),
    dividerTheme: const DividerThemeData(color: Z.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Z.raised,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Z.gold, width: 1.5)),
      labelStyle: const TextStyle(color: Z.muted),
      hintStyle: const TextStyle(color: Z.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(fontFamily: 'Heebo', fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: Z.text,
        side: const BorderSide(color: Z.line),
        textStyle: const TextStyle(fontFamily: 'Heebo', fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: const WidgetStatePropertyAll(BorderSide(color: Z.line)),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Z.gold : Z.raised),
        foregroundColor:
            WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Color(0xFF2A1F00) : Z.text),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: Z.raised,
      side: BorderSide(color: Z.line),
      labelStyle: TextStyle(fontFamily: 'Heebo', color: Z.text, fontWeight: FontWeight.w600),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Z.surface,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: Z.surface),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Z.raised,
      contentTextStyle: TextStyle(fontFamily: 'Heebo', color: Z.text),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Z.surface,
      indicatorColor: Z.gold.withValues(alpha: .18),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? Z.gold : Z.muted)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontFamily: 'Heebo',
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: s.contains(WidgetState.selected) ? Z.gold : Z.muted)),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Z.gold,
      unselectedLabelColor: Z.muted,
      indicatorColor: Z.gold,
      dividerColor: Z.line,
      labelStyle: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w800, fontSize: 15),
      unselectedLabelStyle: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600, fontSize: 15),
      tabAlignment: TabAlignment.start,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Color(0xFF2A1F00) : Z.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Z.gold : Z.raised),
    ),
  );
}

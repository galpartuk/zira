import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dark ("arena") by default; light is the player's choice. Saved on the device.
class Looks extends ChangeNotifier {
  Looks._();
  static final instance = Looks._();
  static const key = 'zira.theme';

  bool light = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    light = p.getString(key) == 'light';
    notifyListeners();
  }

  Future<void> toggle() async {
    light = !light;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(key, light ? 'light' : 'dark');
  }
}

class _Palette {
  final Color ink, surface, raised, line, text, muted, accent, onAccent, blue, coral, win, danger, amber;
  const _Palette({
    required this.ink,
    required this.surface,
    required this.raised,
    required this.line,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.blue,
    required this.coral,
    required this.win,
    required this.danger,
    required this.amber,
  });
}

const _dark = _Palette(
  ink: Color(0xFF0C0F14),
  surface: Color(0xFF161B23),
  raised: Color(0xFF1E2530),
  line: Color(0xFF2A323F),
  text: Color(0xFFF2F4F7),
  muted: Color(0xFF8C95A5),
  accent: Color(0xFFF2F4F7),
  onAccent: Color(0xFF0C0F14),
  blue: Color(0xFF3DB8F5),
  coral: Color(0xFFFF6B4A),
  win: Color(0xFF4FD08A),
  danger: Color(0xFFF0524A),
  amber: Color(0xFFF2B84B),
);

const _light = _Palette(
  ink: Color(0xFFF3F5F8),
  surface: Color(0xFFFFFFFF),
  raised: Color(0xFFE8ECF1),
  line: Color(0xFFD3D9E1),
  text: Color(0xFF12161C),
  muted: Color(0xFF5E6877),
  accent: Color(0xFF12161C),
  onAccent: Color(0xFFFFFFFF),
  blue: Color(0xFF0F7FC2),
  coral: Color(0xFFD9482A),
  win: Color(0xFF16864A),
  danger: Color(0xFFC7332B),
  amber: Color(0xFF9A6408),
);

/// Colour tokens, following the chosen look. The two player colours are the
/// app's identity (a duel): blue is player A / bottom / me, coral is player B
/// / top / the opponent. They are used everywhere a "side" exists.
class Z {
  static _Palette get _p => Looks.instance.light ? _light : _dark;

  static Color get ink => _p.ink; // background
  static Color get surface => _p.surface; // cards
  static Color get raised => _p.raised; // inputs, chips
  static Color get line => _p.line; // borders
  static Color get text => _p.text;
  static Color get muted => _p.muted;
  static Color get accent => _p.accent; // primary action
  static Color get onAccent => _p.onAccent;
  static Color get blue => _p.blue;
  static Color get coral => _p.coral;
  static Color get win => _p.win;
  static Color get danger => _p.danger;
  static Color get amber => _p.amber; // waiting / unconfirmed

  static const tabular = [FontFeature.tabularFigures()];

  /// Big numbers (clock, table numbers, scores): narrow scoreboard digits.
  static const digits = 'BarlowCondensed';
}

ThemeData buildTheme() {
  final scheme = ColorScheme(
    brightness: Looks.instance.light ? Brightness.light : Brightness.dark,
    primary: Z.accent,
    onPrimary: Z.onAccent,
    secondary: Z.blue,
    onSecondary: Z.onAccent,
    tertiary: Z.coral,
    onTertiary: Z.onAccent,
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
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Rubik');
  return base.copyWith(
    scaffoldBackgroundColor: Z.ink,
    textTheme: base.textTheme.apply(bodyColor: Z.text, displayColor: Z.text),
    appBarTheme: AppBarTheme(
      backgroundColor: Z.ink,
      foregroundColor: Z.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Rubik', fontSize: 20, fontWeight: FontWeight.w600, color: Z.text),
    ),
    cardTheme: CardThemeData(
      color: Z.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
    ),
    dividerTheme: DividerThemeData(color: Z.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Z.raised,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Z.accent, width: 1.5),
      ),
      labelStyle: TextStyle(color: Z.muted),
      hintStyle: TextStyle(color: Z.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(fontFamily: 'Rubik', fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: Z.text,
        side: BorderSide(color: Z.line),
        textStyle: const TextStyle(fontFamily: 'Rubik', fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: Z.line)),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: 'Rubik', fontWeight: FontWeight.w600)),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Z.accent : Z.raised),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Z.onAccent : Z.text),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Z.raised,
      side: BorderSide(color: Z.line),
      labelStyle: TextStyle(fontFamily: 'Rubik', color: Z.text, fontWeight: FontWeight.w600),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Z.surface,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    ),
    dialogTheme: DialogThemeData(backgroundColor: Z.surface),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Z.raised,
      contentTextStyle: TextStyle(fontFamily: 'Rubik', color: Z.text),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Z.surface,
      indicatorColor: Z.raised,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? Z.accent : Z.muted),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: 'Rubik',
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: s.contains(WidgetState.selected) ? Z.accent : Z.muted,
        ),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: Z.accent,
      unselectedLabelColor: Z.muted,
      indicatorColor: Z.accent,
      dividerColor: Z.line,
      labelStyle: TextStyle(fontFamily: 'Rubik', fontWeight: FontWeight.w700, fontSize: 15),
      unselectedLabelStyle: TextStyle(fontFamily: 'Rubik', fontWeight: FontWeight.w600, fontSize: 15),
      tabAlignment: TabAlignment.start,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Z.onAccent : Z.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Z.accent : Z.raised),
    ),
  );
}

import 'package:flutter/material.dart';

const kHandFont = 'PatrickHand';
const kTitleFont = 'Caveat';

/// Notebook palette. Light = white paper with dark gray rules,
/// dark = the inverse: near-black paper with light gray rules.
@immutable
class NotebookColors extends ThemeExtension<NotebookColors> {
  const NotebookColors({
    required this.desk,
    required this.paper,
    required this.rule,
    required this.columnRule,
    required this.ink,
    required this.fadedInk,
    required this.shadow,
  });

  /// Background around the paper sheet.
  final Color desk;
  final Color paper;
  final Color rule;
  final Color columnRule;
  final Color ink;
  final Color fadedInk;
  final Color shadow;

  static const light = NotebookColors(
    desk: Color(0xFFF1F0EC),
    paper: Color(0xFFFFFFFF),
    rule: Color(0xFF555555),
    columnRule: Color(0xFFA3A3A3),
    ink: Color(0xFF232323),
    fadedInk: Color(0xFF9B9B9B),
    shadow: Color(0x1A000000),
  );

  static const dark = NotebookColors(
    desk: Color(0xFF070707),
    paper: Color(0xFF161616),
    rule: Color(0xFFB0B0B0),
    columnRule: Color(0xFF5A5A5A),
    ink: Color(0xFFEDEDED),
    fadedInk: Color(0xFF747474),
    shadow: Color(0x00000000),
  );

  @override
  NotebookColors copyWith() => this;

  @override
  NotebookColors lerp(NotebookColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return NotebookColors(
      desk: l(desk, other.desk),
      paper: l(paper, other.paper),
      rule: l(rule, other.rule),
      columnRule: l(columnRule, other.columnRule),
      ink: l(ink, other.ink),
      fadedInk: l(fadedInk, other.fadedInk),
      shadow: l(shadow, other.shadow),
    );
  }
}

ThemeData buildTheme(Brightness b) {
  final nb = b == Brightness.light ? NotebookColors.light : NotebookColors.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.grey,
    brightness: b,
    surface: nb.paper,
    onSurface: nb.ink,
    primary: nb.ink,
    onPrimary: nb.paper,
  );
  final base = ThemeData(brightness: b, useMaterial3: true);
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: nb.desk,
    textTheme: base.textTheme.apply(
      fontFamily: kHandFont,
      bodyColor: nb.ink,
      displayColor: nb.ink,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: nb.ink,
      selectionColor: nb.fadedInk.withValues(alpha: 0.35),
      selectionHandleColor: nb.ink,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: nb.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: nb.columnRule.withValues(alpha: 0.5)),
      ),
      textStyle: TextStyle(fontFamily: kHandFont, fontSize: 18, color: nb.ink),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: nb.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titleTextStyle: TextStyle(
        fontFamily: kTitleFont,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: nb.ink,
      ),
      contentTextStyle: TextStyle(
        fontFamily: kHandFont,
        fontSize: 18,
        color: nb.ink,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: nb.ink,
      contentTextStyle: TextStyle(
        fontFamily: kHandFont,
        fontSize: 17,
        color: nb.paper,
      ),
      actionTextColor: nb.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: nb.ink,
        foregroundColor: nb.paper,
        textStyle: const TextStyle(fontFamily: kHandFont, fontSize: 18),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: nb.ink,
        textStyle: const TextStyle(fontFamily: kHandFont, fontSize: 18),
      ),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: nb.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      helpTextStyle: TextStyle(fontFamily: kHandFont, fontSize: 18, color: nb.fadedInk),
      hourMinuteColor: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.selected)
          ? nb.ink
          : nb.columnRule.withValues(alpha: 0.18)),
      hourMinuteTextColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected) ? nb.paper : nb.ink),
      hourMinuteTextStyle: const TextStyle(fontFamily: kHandFont, fontSize: 52),
      dialBackgroundColor: nb.columnRule.withValues(alpha: 0.18),
      dialHandColor: nb.ink,
      dialTextColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected) ? nb.paper : nb.ink),
      entryModeIconColor: nb.ink,
      cancelButtonStyle: TextButton.styleFrom(foregroundColor: nb.ink),
      confirmButtonStyle: TextButton.styleFrom(foregroundColor: nb.ink),
    ),
    extensions: [nb],
  );
}

extension NotebookContext on BuildContext {
  NotebookColors get nb => Theme.of(this).extension<NotebookColors>()!;
}

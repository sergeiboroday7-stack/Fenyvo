import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// SPARTAN: midnight blue surfaces and restrained champagne-gold accents.
abstract final class SpartanPalette {
  static const canvas = Color(0xFF122238);
  static const surface = Color(0xFF1A2D43);
  static const ink = Color(0xFFE5E9EF);
  static const secondary = Color(0xFFB0BFCE);
  static const muted = Color(0xFF9AACBC);
  static const line = Color(0xFF2D4359);
  static const blue = Color(0xFF294564);
  static const blueDeep = Color(0xFF294564);
  static const gold = Color(0xFFC7A65C);
  static const onGold = Color(0xFF15263A);
  static const rail = Color(0xFF0D1B2B);
  static const mediaAccent = Color(0xFFFFFFFF);

  static ThemeData get blueGoldTheme {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.dark,
        ).copyWith(
          primary: gold,
          onPrimary: onGold,
          primaryContainer: blue,
          onPrimaryContainer: ink,
          secondary: gold,
          secondaryContainer: blue,
          onSecondaryContainer: ink,
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: secondary,
          outline: line,
          outlineVariant: line,
          surfaceTint: Colors.transparent,
        );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      dividerColor: line,
      iconTheme: const IconThemeData(color: ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: blue,
        contentTextStyle: TextStyle(color: ink),
        actionTextColor: gold,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: blue,
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: surface,
        textStyle: TextStyle(color: ink),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: blue,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: const TextStyle(color: secondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: line),
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: gold,
        selectionColor: blue,
        selectionHandleColor: gold,
      ),
    );
  }

  // Compatibility for existing screens/tests; app uses blueGoldTheme explicitly.
  static ThemeData get lightTheme => blueGoldTheme;
  static ThemeData get callTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0A0A0A),
    colorScheme: ColorScheme.fromSeed(
      seedColor: gold,
      brightness: Brightness.dark,
    ),
  );
}

/// Retains the same child location during calls. No decorative overlay or glow.
class SpartanLightFrame extends StatelessWidget {
  const SpartanLightFrame({
    super.key,
    required this.child,
    this.enabled = true,
  });
  final Widget child;
  final bool enabled;
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: SpartanPalette.canvas,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
    child: Stack(fit: StackFit.expand, children: [child]),
  );
}

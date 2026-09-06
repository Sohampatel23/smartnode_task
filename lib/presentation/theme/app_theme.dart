import 'package:flutter/material.dart';

/// Centralized visual design tokens. Kept as one small file so the app's
/// look can be tuned in one place rather than scattered `Color(0xFF...)`
/// literals through the widget tree.
///
/// Palette rationale: a steady industrial navy for structure/trust (this is
/// operational software, not a consumer app) with a warm amber accent used
/// sparingly for things that need attention (low stock, pending sync) - the
/// same visual language as hazard/inventory signage on an actual warehouse
/// floor, without leaning on literal yellow-and-black stripes.
class AppTheme {
  AppTheme._();

  static const Color _navy = Color(0xFF1E3A5F);
  static const Color _amber = Color(0xFFF59E0B);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _navy,
      secondary: _amber,
      brightness: Brightness.light,
    );
    return _themeFrom(scheme);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _navy,
      secondary: _amber,
      brightness: Brightness.dark,
    );
    return _themeFrom(scheme);
  }

  static ThemeData _themeFrom(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      textTheme: const TextTheme().apply(
        fontSizeFactor: 1.0,
      ),
    );
  }

  /// Warm amber used for "needs attention" affordances (low stock, pending
  /// sync) - distinct from the red used for the offline/error state so the
  /// two severities never visually collide.
  static Color attention(BuildContext context) => _amber;
}

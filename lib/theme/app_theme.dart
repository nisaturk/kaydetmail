import 'package:flutter/material.dart';

/// Visual language: white/black background, black text, black accents, grey
/// secondary text, light grey borders. Minimal and professional. A dark
/// variant mirrors the same language inverted — see [dark] and [darkColors].
///
/// Spacing/radius/typography are plain [double]/[TextStyle] constants (safe
/// to use in `const` contexts everywhere). Colors that must flip between
/// light and dark live in [AppColors], a [ThemeExtension] read through
/// [AppTheme.colors] — those need a [BuildContext] and can't be `const`.
class AppTheme {
  const AppTheme._();

  // --- Spacing scale (4px base) --------------------------------------
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;

  // --- Radius scale ---------------------------------------------------
  static const double radiusSmall = 8;
  static const double radiusMedium = 10;
  static const double radiusLarge = 12;
  static const double radiusPill = 999;

  // --- Touch targets ----------------------------------------------------
  /// WCAG 2.1 minimum recommended touch target size for any custom gesture
  /// (color swatches, custom icon buttons, swipe affordances).
  static const double minTouchTarget = 48;

  // --- Icon sizes -------------------------------------------------------
  static const double iconSizeSmall = 14;
  static const double iconSizeMedium = 18;
  static const double iconSizeLarge = 20;

  // --- Typography scale ---------------------------------------------
  static const TextStyle displayText = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );
  static const TextStyle titleText = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );
  static const TextStyle bodyLargeText = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
  static const TextStyle bodyText2 = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );
  static const TextStyle captionText = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  // --- Legacy light-only static colors ---------------------------------
  // Kept for any remaining `const` callsite; prefer `AppTheme.colors(context)`
  // in real widget builds so dark mode picks up the right values.
  static const Color border = Color(0xFFE5E7EB);
  static const Color secondaryText = Color(0xFF6B7280);
  static const Color tertiaryText = Color(0xFF5B6472);
  static const Color bodyText = Color(0xFF1F2937);
  static const Color unreadBackground = Color(0xFFF9FAFB);

  /// Resolves the brightness-aware color tokens for the current [context].
  /// Falls back to [AppColors.light] if the extension is somehow missing
  /// (e.g. a widget test builds raw `ThemeData` without [AppTheme.light]).
  static AppColors colors(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? AppColors.light;

  static ThemeData get light => _build(Brightness.light, AppColors.light);
  static ThemeData get dark => _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness brightness, AppColors colors) {
    final isDark = brightness == Brightness.dark;
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0B0B0B),
      brightness: brightness,
    );
    final onSurface = isDark ? Colors.white : Colors.black;
    final surface = isDark ? const Color(0xFF121316) : Colors.white;
    final scheme = base.copyWith(
      primary: isDark ? Colors.white : Colors.black,
      onPrimary: isDark ? Colors.black : Colors.white,
      secondary: isDark ? const Color(0xFFE5E7EB) : const Color(0xFF1F2937),
      onSecondary: isDark ? Colors.black : Colors.white,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: colors.surfaceAlt,
      outline: colors.border,
      error: colors.destructive,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [colors],
      scaffoldBackgroundColor: surface,
      fontFamily: null,
      textTheme: Typography.material2021(platform: TargetPlatform.android).black
          .apply(bodyColor: onSurface, displayColor: onSurface),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: titleText.copyWith(color: onSurface),
        iconTheme: IconThemeData(color: onSurface),
      ),
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.secondaryText,
        textColor: onSurface,
        selectedTileColor: colors.surfaceAlt,
        selectedColor: onSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: space4,
          vertical: space1,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(minTouchTarget),
          foregroundColor: onSurface,
          disabledForegroundColor: colors.tertiaryText,
        ),
      ),
      iconTheme: IconThemeData(color: onSurface),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: isDark ? Colors.white : Colors.black,
        foregroundColor: isDark ? Colors.black : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(radiusLarge),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
        titleTextStyle: titleText.copyWith(color: onSurface),
        contentTextStyle: bodyText2.copyWith(color: colors.secondaryText),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: BorderSide(color: colors.border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceAlt,
        selectedColor: onSurface,
        labelStyle: captionText.copyWith(color: onSurface),
        secondaryLabelStyle: captionText.copyWith(
          color: isDark ? Colors.black : Colors.white,
        ),
        side: BorderSide(color: colors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusPill),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: space3,
          vertical: space1,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.unreadBackground,
        hintStyle: TextStyle(color: colors.tertiaryText),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide(color: onSurface, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: isDark ? Colors.white : Colors.black,
          foregroundColor: isDark ? Colors.black : Colors.white,
          disabledBackgroundColor: colors.border,
          disabledForegroundColor: colors.tertiaryText,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLarge),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: onSurface,
          disabledForegroundColor: colors.tertiaryText,
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark
            ? const Color(0xFF2A2D34)
            : const Color(0xFF1F2937),
        contentTextStyle: const TextStyle(color: Colors.white),
        actionTextColor: Colors.white,
        behavior: SnackBarBehavior.floating,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: onSurface,
        textColor: surface,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2D34) : const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

/// Brightness-aware color tokens not modeled directly by [ColorScheme].
/// Registered on [ThemeData.extensions] by [AppTheme.light]/[AppTheme.dark]
/// — read with `AppTheme.colors(context)`, never construct directly.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.border,
    required this.secondaryText,
    required this.tertiaryText,
    required this.bodyText,
    required this.unreadBackground,
    required this.surfaceAlt,
    required this.destructive,
    required this.success,
    required this.warning,
    required this.warningBackground,
  });

  /// Hairline dividers, outlines, unselected borders.
  final Color border;

  /// De-emphasized text: subtitles, senders, metadata rows. Meets WCAG AA
  /// (>=4.5:1) against [Scaffold]'s background.
  final Color secondaryText;

  /// Least-emphasized text/icons (timestamps, tiny status icons). Also
  /// meets WCAG AA — hierarchy below [secondaryText] comes from size/weight,
  /// not from dropping under the accessible contrast floor.
  final Color tertiaryText;

  /// Near-black/near-white main text for long-form content (mail bodies).
  final Color bodyText;

  /// Barely-tinted row background marking unread mails / default input fill.
  final Color unreadBackground;

  /// Selected-row / chip / tag background — one step off the base surface.
  final Color surfaceAlt;

  /// Destructive actions and error text (delete, close session, validation).
  final Color destructive;

  /// Positive/healthy status (API connection OK).
  final Color success;

  /// Warning icon/text color, paired with [warningBackground].
  final Color warning;

  /// Warning banner fill (offline/no-connection notices).
  final Color warningBackground;

  static const light = AppColors(
    border: Color(0xFFE5E7EB),
    secondaryText: Color(0xFF6B7280),
    tertiaryText: Color(0xFF5B6472),
    bodyText: Color(0xFF1F2937),
    unreadBackground: Color(0xFFF9FAFB),
    surfaceAlt: Color(0xFFF3F4F6),
    destructive: Color(0xFFB3261E),
    success: Color(0xFF2E7D32),
    warning: Color(0xFF8A6D00),
    warningBackground: Color(0xFFFFF3CD),
  );

  static const dark = AppColors(
    border: Color(0xFF2A2D34),
    secondaryText: Color(0xFF9CA3AF),
    tertiaryText: Color(0xFF9AA4B2),
    bodyText: Color(0xFFE5E7EB),
    unreadBackground: Color(0xFF17191D),
    surfaceAlt: Color(0xFF20232A),
    destructive: Color(0xFFE57373),
    success: Color(0xFF66BB6A),
    warning: Color(0xFFE0B84B),
    warningBackground: Color(0xFF3A2E00),
  );

  @override
  AppColors copyWith({
    Color? border,
    Color? secondaryText,
    Color? tertiaryText,
    Color? bodyText,
    Color? unreadBackground,
    Color? surfaceAlt,
    Color? destructive,
    Color? success,
    Color? warning,
    Color? warningBackground,
  }) {
    return AppColors(
      border: border ?? this.border,
      secondaryText: secondaryText ?? this.secondaryText,
      tertiaryText: tertiaryText ?? this.tertiaryText,
      bodyText: bodyText ?? this.bodyText,
      unreadBackground: unreadBackground ?? this.unreadBackground,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      destructive: destructive ?? this.destructive,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      warningBackground: warningBackground ?? this.warningBackground,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    // Discrete light/dark tokens (no continuous animation between them
    // today) — step at the midpoint rather than pretending to interpolate
    // hand-picked palettes.
    if (other is! AppColors) return this;
    return t < 0.5 ? this : other;
  }
}

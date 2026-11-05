import 'package:flutter/material.dart';

import 'tokens.dart';

/// Tema Material costruito a mano dai token (niente colorSchemeSeed).
ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? ScontriniColors.dark : ScontriniColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    surface: c.background,
    onSurface: c.onSurface,
    surfaceContainerLowest: c.background,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surfaceHigh,
    surfaceContainerHighest: c.surfaceHigh,
    onSurfaceVariant: c.onSurfaceMuted,
    outline: c.outlineStrong,
    outlineVariant: c.outline,
    primary: c.primary,
    onPrimary: c.onCta,
    primaryContainer: c.summaryCard,
    onPrimaryContainer: c.onSummaryCard,
    secondary: c.primary,
    onSecondary: c.onCta,
    tertiary: c.warning,
    onTertiary: c.onCta,
    tertiaryContainer: c.warningContainer,
    onTertiaryContainer: c.onWarningContainer,
    inverseSurface: c.cta,
    onInverseSurface: c.onCta,
    inversePrimary: c.summaryCard,
    error: c.error,
    onError: c.onCta,
    errorContainer: c.surfaceHigh,
    onErrorContainer: c.error,
    scrim: c.scrim,
    shadow: Colors.transparent,
  );

  TextStyle t(TextStyle s, [Color? color]) => s.copyWith(color: color ?? c.onSurface);
  final textTheme = TextTheme(
    displaySmall: t(AppText.amountHero),
    headlineLarge: t(AppText.headlineOnboarding),
    headlineMedium: t(AppText.headline),
    headlineSmall: t(AppText.amountLarge),
    titleLarge: t(AppText.title),
    titleMedium: t(AppText.titleSmall),
    titleSmall: t(AppText.titleSmall),
    bodyLarge: t(AppText.body),
    bodyMedium: t(AppText.body),
    bodySmall: t(AppText.bodySmall, c.onSurfaceMuted),
    labelLarge: t(AppText.button),
    labelMedium: t(AppText.label),
    labelSmall: t(AppText.badge),
  );

  final stadium = WidgetStatePropertyAll<OutlinedBorder>(const StadiumBorder());
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.input),
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: AppText.family,
    textTheme: textTheme,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    splashFactory: InkSparkle.splashFactory,
    extensions: [c],
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: t(AppText.title),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.cta.withValues(alpha: 0.38) : c.cta),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.onCta.withValues(alpha: 0.7) : c.onCta),
        shape: stadium,
        minimumSize: const WidgetStatePropertyAll(Size(64, Sizes.button)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Gap.xl)),
        textStyle: const WidgetStatePropertyAll(AppText.button),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(c.onSurface),
        side: WidgetStatePropertyAll(BorderSide(color: c.outlineStrong)),
        shape: stadium,
        minimumSize: const WidgetStatePropertyAll(Size(64, Sizes.button)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Gap.xl)),
        textStyle: const WidgetStatePropertyAll(AppText.button),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(c.primary),
        textStyle: const WidgetStatePropertyAll(AppText.button),
        shape: stadium,
        minimumSize: const WidgetStatePropertyAll(Size(Sizes.touch, Sizes.touch)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(c.onSurface),
        minimumSize: const WidgetStatePropertyAll(Size(Sizes.touch, Sizes.touch)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 17),
      hintStyle: AppText.body.copyWith(color: c.onSurfaceMuted),
      prefixIconColor: c.onSurfaceMuted,
      suffixIconColor: c.onSurfaceMuted,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      errorStyle: AppText.bodySmall.copyWith(color: c.error),
      border: border(c.outline, 1),
      enabledBorder: border(c.outline, 1),
      focusedBorder: border(c.primary, 1.5),
      errorBorder: border(c.error, 1),
      focusedErrorBorder: border(c.error, 1.5),
      disabledBorder: border(c.outline, 1),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.primary,
      selectionColor: c.primary.withValues(alpha: 0.35),
      selectionHandleColor: c.primary,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      modalBackgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: c.outlineStrong,
      dragHandleSize: const Size(40, 5),
      modalBarrierColor: c.scrim,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      barrierColor: c.scrim,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
      titleTextStyle: t(AppText.title),
      contentTextStyle: t(AppText.body, c.onSurfaceMuted),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ),
    dividerTheme: const DividerThemeData(color: Colors.transparent, thickness: 0, space: 0),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.cta,
      contentTextStyle: AppText.bodySmall.copyWith(color: c.onCta),
      actionTextColor: c.onCta,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.input)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      textStyle: t(AppText.titleSmall),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.input)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary, linearTrackColor: c.surfaceHigh),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.onSurfaceMuted,
      textColor: c.onSurface,
      titleTextStyle: t(AppText.titleSmall),
      subtitleTextStyle: t(AppText.bodySmall, c.onSurfaceMuted),
    ),
  );
}

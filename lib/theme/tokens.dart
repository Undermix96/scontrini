import 'package:flutter/material.dart';

/// Token del design system. Fonte: docs/design/README.md e docs/design/tokens.json.
///
/// Tutti i colori dell'interfaccia vengono da qui: le schermate non devono
/// contenere valori esadecimali.
@immutable
class ScontriniColors extends ThemeExtension<ScontriniColors> {
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color outline;
  final Color outlineStrong;
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color primary;
  final Color summaryCard;
  final Color onSummaryCard;
  final Color onSummaryCardMuted;
  final Color cta;
  final Color onCta;
  final Color navBar;
  final Color navBarOutline;
  final Color navActiveIcon;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color warningOutline;
  final Color error;
  final Color success;
  final Color scrim;

  const ScontriniColors({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.outline,
    required this.outlineStrong,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.primary,
    required this.summaryCard,
    required this.onSummaryCard,
    required this.onSummaryCardMuted,
    required this.cta,
    required this.onCta,
    required this.navBar,
    required this.navBarOutline,
    required this.navActiveIcon,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.warningOutline,
    required this.error,
    required this.success,
    required this.scrim,
  });

  static const dark = ScontriniColors(
    background: Color(0xFF0C0C10),
    surface: Color(0xFF17171D),
    surfaceHigh: Color(0xFF22222A),
    outline: Color(0xFF2C2C36),
    outlineStrong: Color(0xFF3A3A46),
    onSurface: Color(0xFFF4F3F8),
    onSurfaceMuted: Color(0xFFA3A1B3),
    primary: Color(0xFFA99CFF),
    summaryCard: Color(0xFFA598FF),
    onSummaryCard: Color(0xFF14112B),
    onSummaryCardMuted: Color(0xFF3A3370),
    cta: Color(0xFFF4F3F8),
    onCta: Color(0xFF0C0C10),
    navBar: Color(0xFF22222A),
    navBarOutline: Color(0xFF33333E),
    navActiveIcon: Color(0xFF5B4BDB),
    warning: Color(0xFFF5B14C),
    warningContainer: Color(0xFF3A2C12),
    onWarningContainer: Color(0xFFFFD99A),
    warningOutline: Color(0xFF7A5A22),
    error: Color(0xFFFF8A80),
    success: Color(0xFF5FD39B),
    scrim: Color(0x99000000),
  );

  static const light = ScontriniColors(
    background: Color(0xFFF4F3F8),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFECEAF4),
    outline: Color(0xFFE0DEEA),
    outlineStrong: Color(0xFFD3D0E0),
    onSurface: Color(0xFF14131A),
    onSurfaceMuted: Color(0xFF5E5B6E),
    primary: Color(0xFF5B4BDB),
    summaryCard: Color(0xFFB4A9FF),
    onSummaryCard: Color(0xFF14112B),
    onSummaryCardMuted: Color(0xFF3A3370),
    cta: Color(0xFF14131A),
    onCta: Color(0xFFFFFFFF),
    navBar: Color(0xFFFFFFFF),
    navBarOutline: Color(0xFFE0DEEA),
    navActiveIcon: Color(0xFFB4A9FF),
    warning: Color(0xFFB86E00),
    warningContainer: Color(0xFFFFF1DA),
    onWarningContainer: Color(0xFF6B4000),
    warningOutline: Color(0xFFE3C38E),
    error: Color(0xFFC62828),
    success: Color(0xFF1B7F4E),
    scrim: Color(0x6114131A),
  );

  /// Colori fissi della card di riepilogo (uguali nei due temi).
  static const summaryInk = Color(0xFF14112B);
  static const summaryGhost = Color(0x8CFFFFFF); // bianco al 55%

  /// Colore per le righe senza categoria.
  static const uncategorized = Color(0xFF8E8C9C);

  @override
  ScontriniColors copyWith() => this;

  @override
  ScontriniColors lerp(ScontriniColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return ScontriniColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceHigh: l(surfaceHigh, other.surfaceHigh),
      outline: l(outline, other.outline),
      outlineStrong: l(outlineStrong, other.outlineStrong),
      onSurface: l(onSurface, other.onSurface),
      onSurfaceMuted: l(onSurfaceMuted, other.onSurfaceMuted),
      primary: l(primary, other.primary),
      summaryCard: l(summaryCard, other.summaryCard),
      onSummaryCard: l(onSummaryCard, other.onSummaryCard),
      onSummaryCardMuted: l(onSummaryCardMuted, other.onSummaryCardMuted),
      cta: l(cta, other.cta),
      onCta: l(onCta, other.onCta),
      navBar: l(navBar, other.navBar),
      navBarOutline: l(navBarOutline, other.navBarOutline),
      navActiveIcon: l(navActiveIcon, other.navActiveIcon),
      warning: l(warning, other.warning),
      warningContainer: l(warningContainer, other.warningContainer),
      onWarningContainer: l(onWarningContainer, other.onWarningContainer),
      warningOutline: l(warningOutline, other.warningOutline),
      error: l(error, other.error),
      success: l(success, other.success),
      scrim: l(scrim, other.scrim),
    );
  }
}

extension ScontriniTheme on BuildContext {
  ScontriniColors get colors => Theme.of(this).extension<ScontriniColors>()!;
}

/// Colori proposti per le categorie, con il nome per l'accessibilità.
class PaletteColor {
  final String name;
  final String hex;
  const PaletteColor(this.name, this.hex);
  Color get color => Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

const categoryPalette = [
  PaletteColor('Verde', '#4CC38A'),
  PaletteColor('Azzurro', '#5AA9F0'),
  PaletteColor('Arancio', '#F0A35A'),
  PaletteColor('Rosa', '#E67AC4'),
  PaletteColor('Rosso', '#F26D6D'),
  PaletteColor('Sabbia', '#C9A76B'),
  PaletteColor('Lavanda', '#A99CFF'),
  PaletteColor('Grigio', '#8E8C9C'),
  PaletteColor('Turchese', '#6FD3D3'),
  PaletteColor('Giallo', '#E8D45A'),
  PaletteColor('Blu', '#7C8CF8'),
  PaletteColor('Terra', '#B07A5A'),
];

/// Stili tipografici (senza colore: lo eredita dal tema o va passato).
class AppText {
  static const family = 'Manrope';
  static const _tab = [FontFeature.tabularFigures()];

  static const amountHero = TextStyle(
      fontFamily: family, fontSize: 42, fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.05, fontFeatures: _tab);
  static const amountLarge =
      TextStyle(fontFamily: family, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6, fontFeatures: _tab);
  static const amount = TextStyle(fontFamily: family, fontSize: 16, fontWeight: FontWeight.w800, fontFeatures: _tab);
  static const amountSmall = TextStyle(fontFamily: family, fontSize: 15, fontWeight: FontWeight.w800, fontFeatures: _tab);
  static const headline = TextStyle(fontFamily: family, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5);
  static const headlineOnboarding =
      TextStyle(fontFamily: family, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.15);
  static const title = TextStyle(fontFamily: family, fontSize: 18, fontWeight: FontWeight.w800);
  static const titleSmall = TextStyle(fontFamily: family, fontSize: 15, fontWeight: FontWeight.w700);
  static const body = TextStyle(fontFamily: family, fontSize: 15, fontWeight: FontWeight.w500, height: 1.5);
  static const bodySmall = TextStyle(fontFamily: family, fontSize: 13, fontWeight: FontWeight.w600, height: 1.45);
  static const label = TextStyle(fontFamily: family, fontSize: 13, fontWeight: FontWeight.w700);
  static const badge = TextStyle(fontFamily: family, fontSize: 12, fontWeight: FontWeight.w700);
  static const button = TextStyle(fontFamily: family, fontSize: 16, fontWeight: FontWeight.w700);
  static const buttonSmall = TextStyle(fontFamily: family, fontSize: 13, fontWeight: FontWeight.w700);
}

/// Spaziature (base 4).
class Gap {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
  static const gutter = 20.0;

  /// Larghezza massima del contenuto su schermi larghi.
  static const maxContent = 560.0;
}

class Radii {
  static const sm = 12.0;
  static const chip = 14.0;
  static const input = 16.0;
  static const md = 20.0;
  static const card = 24.0;
  static const lg = 28.0;
  static const sheet = 32.0;
  static const pill = 999.0;
}

class Sizes {
  static const touch = 44.0;
  static const iconButton = 44.0;
  static const button = 56.0;
  static const buttonCompact = 52.0;
  static const chip = 36.0;
  static const input = 56.0;
  static const navItem = 48.0;
  static const fab = 62.0;
  static const avatar = 44.0;
}

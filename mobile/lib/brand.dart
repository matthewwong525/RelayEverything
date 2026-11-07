import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Relay Everything's look: the *Emerald* color set, light and dark, Inter, and the mark. `wiki/brand.md` owns the
/// values and the rules; this file is their one copy in the app, so `app.dart` and the share card can not drift.
@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors({required this.paper, required this.card, required this.line, required this.ink, required this.muted,
    required this.accent, required this.onAccent, required this.accentText, required this.accentSoft, required this.spark,
    required this.onSpark, required this.danger, required this.onDanger});

  /// The screen background.
  final Color paper;
  /// Cards and quiet buttons: a lighter shape on paper.
  final Color card;
  /// Rare dividers.
  final Color line;
  /// Text.
  final Color ink;
  /// Supporting text.
  final Color muted;
  /// The one main action's fill.
  final Color accent;
  /// Text on [accent].
  final Color onAccent;
  /// The accent as text, and the logo on paper.
  final Color accentText;
  /// Tag background and glow.
  final Color accentSoft;
  /// Small live moments: a voice note, recording.
  final Color spark;
  /// Text on [spark].
  final Color onSpark;
  /// Errors.
  final Color danger;
  /// Text on [danger].
  final Color onDanger;

  static const light = BrandColors(
    paper: Color(0xFFF7F8F4), card: Color(0xFFFFFFFF), line: Color(0xFFE3E6DF), ink: Color(0xFF121614),
    muted: Color(0xFF5E6660), accent: Color(0xFF0E7A5A), onAccent: Color(0xFFFFFFFF), accentText: Color(0xFF0E7A5A),
    accentSoft: Color(0xFFE1F2EA), spark: Color(0xFFF5A524), onSpark: Color(0xFF121614), danger: Color(0xFFC9302C),
    onDanger: Color(0xFFFFFFFF));

  static const dark = BrandColors(
    paper: Color(0xFF0C110F), card: Color(0xFF161D1A), line: Color(0xFF26302B), ink: Color(0xFFECF3EE),
    muted: Color(0xFF9AA8A0), accent: Color(0xFF4CC79A), onAccent: Color(0xFF06281A), accentText: Color(0xFF4CC79A),
    accentSoft: Color(0xFF133328), spark: Color(0xFFFFC24D), onSpark: Color(0xFF121614), danger: Color(0xFFFF8A80),
    onDanger: Color(0xFF0C110F));

  /// The set for [brightness].
  static BrandColors of(Brightness brightness) => brightness == Brightness.dark ? dark : light;

  @override
  BrandColors copyWith({Color? paper, Color? card, Color? line, Color? ink, Color? muted, Color? accent, Color? onAccent,
      Color? accentText, Color? accentSoft, Color? spark, Color? onSpark, Color? danger, Color? onDanger}) =>
    BrandColors(paper: paper ?? this.paper, card: card ?? this.card, line: line ?? this.line, ink: ink ?? this.ink,
      muted: muted ?? this.muted, accent: accent ?? this.accent, onAccent: onAccent ?? this.onAccent,
      accentText: accentText ?? this.accentText, accentSoft: accentSoft ?? this.accentSoft, spark: spark ?? this.spark,
      onSpark: onSpark ?? this.onSpark, danger: danger ?? this.danger, onDanger: onDanger ?? this.onDanger);

  @override
  BrandColors lerp(BrandColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return BrandColors(paper: mix(paper, other.paper), card: mix(card, other.card), line: mix(line, other.line),
      ink: mix(ink, other.ink), muted: mix(muted, other.muted), accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent), accentText: mix(accentText, other.accentText),
      accentSoft: mix(accentSoft, other.accentSoft), spark: mix(spark, other.spark), onSpark: mix(onSpark, other.onSpark),
      danger: mix(danger, other.danger), onDanger: mix(onDanger, other.onDanger));
  }
}

/// The brand's one font family, bundled in `assets/fonts/inter/` so the app shows it with no network call.
const brandFont = 'Inter';

/// Semi-bold between Inter's 500 and 700: headings and button labels.
const _semi = FontWeight(650);

/// Corners: 12 on buttons and fields, 16 on cards.
const _field = BorderRadius.all(Radius.circular(12));
const _cardCorners = BorderRadius.all(Radius.circular(16));

/// The app's theme for [brightness]: every [ColorScheme] slot set from [BrandColors], so no Material widget shows a
/// generated tint, and Inter at the brand's type scale.
ThemeData brandTheme(Brightness brightness) {
  final c = BrandColors.of(brightness);
  final other = BrandColors.of(brightness == Brightness.dark ? Brightness.light : Brightness.dark);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent, onPrimary: c.onAccent,
    primaryContainer: c.accentSoft, onPrimaryContainer: c.accentText,
    primaryFixed: c.accentSoft, primaryFixedDim: c.accentSoft, onPrimaryFixed: c.accentText, onPrimaryFixedVariant: c.accentText,
    // Selected chips, segments and tonal buttons stay ink on a quiet fill: the accent is for the one main action.
    secondary: c.ink, onSecondary: c.paper,
    secondaryContainer: c.line, onSecondaryContainer: c.ink,
    secondaryFixed: c.line, secondaryFixedDim: c.line, onSecondaryFixed: c.ink, onSecondaryFixedVariant: c.ink,
    tertiary: c.spark, onTertiary: c.onSpark,
    tertiaryContainer: c.spark, onTertiaryContainer: c.onSpark,
    tertiaryFixed: c.spark, tertiaryFixedDim: c.spark, onTertiaryFixed: c.onSpark, onTertiaryFixedVariant: c.onSpark,
    error: c.danger, onError: c.onDanger,
    errorContainer: c.danger, onErrorContainer: c.onDanger,
    surface: c.paper, onSurface: c.ink, onSurfaceVariant: c.muted,
    surfaceDim: c.paper, surfaceBright: c.card,
    surfaceContainerLowest: c.card, surfaceContainerLow: c.card, surfaceContainer: c.card,
    surfaceContainerHigh: c.card, surfaceContainerHighest: c.card,
    outline: c.muted, outlineVariant: c.line,
    shadow: Colors.black, scrim: Colors.black,
    inverseSurface: c.ink, onInverseSurface: c.paper, inversePrimary: other.accentText,
    surfaceTint: Colors.transparent,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: brandFont, brightness: brightness);
  final text = base.textTheme.copyWith(
    // The large app bar's title: *Notes* and *Settings*.
    headlineMedium: base.textTheme.headlineMedium?.copyWith(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.64),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.56),
    titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: _semi, letterSpacing: -0.4),
    titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: _semi),
    // Inter is drawn for text with no added letter spacing; Material's own 0.25 to 0.5 reads loose in it.
    bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16, letterSpacing: 0),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 16, letterSpacing: 0),
    bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 13, letterSpacing: 0),
    labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: _semi),
  ).apply(bodyColor: c.ink, displayColor: c.ink);

  final glow = WidgetStateProperty.resolveWith<double>((states) => states.contains(WidgetState.disabled) ? 0 : 3);
  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: c.paper,
    extensions: [c],
    // No titleTextStyle: it would also set the large app bar's expanded title, which takes headlineMedium.
    appBarTheme: AppBarTheme(
      backgroundColor: c.paper, foregroundColor: c.ink, surfaceTintColor: Colors.transparent, scrolledUnderElevation: 0),
    cardTheme: CardThemeData(color: c.card, surfaceTintColor: Colors.transparent, elevation: 0, margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: _cardCorners)),
    listTileTheme: ListTileThemeData(
      titleTextStyle: text.bodyLarge?.copyWith(color: c.ink),
      subtitleTextStyle: text.bodySmall?.copyWith(color: c.muted)),
    filledButtonTheme: FilledButtonThemeData(style: ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled) ? null : c.accent),
      foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled) ? null : c.onAccent),
      elevation: glow,
      shadowColor: WidgetStatePropertyAll(c.accent),
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: _field)),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(foregroundColor: c.ink,
      side: BorderSide(color: c.line, width: 1.5), shape: const RoundedRectangleBorder(borderRadius: _field))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.accentText,
      shape: const RoundedRectangleBorder(borderRadius: _field))),
    floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: c.accent, foregroundColor: c.onAccent,
      elevation: 4, focusElevation: 4, hoverElevation: 6, highlightElevation: 2, shape: const StadiumBorder(),
      extendedTextStyle: text.labelLarge?.copyWith(fontSize: 16, fontWeight: _semi)),
    chipTheme: ChipThemeData(backgroundColor: c.line, side: BorderSide.none, shape: const StadiumBorder(),
      labelStyle: text.bodySmall?.copyWith(fontWeight: FontWeight.w500, color: c.ink), iconTheme: IconThemeData(color: c.muted)),
    inputDecorationTheme: InputDecorationThemeData(
      enabledBorder: OutlineInputBorder(borderRadius: _field, borderSide: BorderSide(color: c.line, width: 1.5)),
      disabledBorder: OutlineInputBorder(borderRadius: _field, borderSide: BorderSide(color: c.line)),
      focusedBorder: OutlineInputBorder(borderRadius: _field, borderSide: BorderSide(color: c.accentText, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: _field, borderSide: BorderSide(color: c.danger, width: 1.5)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: _field, borderSide: BorderSide(color: c.danger, width: 2)),
    ),
    dialogTheme: DialogThemeData(backgroundColor: c.card, surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: _cardCorners)),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.card, surfaceTintColor: Colors.transparent),
    dividerTheme: DividerThemeData(color: c.line),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
  );
}

/// The brand colors in this [context]'s theme.
BrandColors brandOf(BuildContext context) =>
  Theme.of(context).extension<BrandColors>() ?? BrandColors.of(Theme.of(context).brightness);

/// Gives [child]'s shadow the accent color: the soft glow on the one main action, such as *New note*.
class AccentGlow extends StatelessWidget {
  const AccentGlow({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(data: theme.copyWith(shadowColor: brandOf(context).accent.withValues(alpha: 0.6)), child: child);
  }
}

/// A small pill with a word: *Voice* and *Listening* in the spark color, a small live moment; *Typed* in accent text on
/// accent soft. [large] is the size on a note's page and the listening card.
class BrandTag extends StatelessWidget {
  const BrandTag(this.label, {super.key, this.spark = false, this.large = false});

  final String label;
  final bool spark;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return DecoratedBox(
      decoration: ShapeDecoration(color: spark ? brand.spark : brand.accentSoft, shape: const StadiumBorder()),
      child: Padding(
        padding: large ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4) : const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(label, style: TextStyle(fontSize: large ? 13 : 11, fontWeight: _semi,
          color: spark ? brand.onSpark : brand.accentText)),
      ),
    );
  }
}

/// A quiet button: ink on [BrandColors.paper], for a second action inside a card, such as *Remove* or *Cancel*.
ButtonStyle quietButton(BuildContext context) {
  final brand = brandOf(context);
  return TextButton.styleFrom(backgroundColor: brand.paper, foregroundColor: brand.ink,
    textStyle: const TextStyle(fontSize: 15, fontWeight: _semi));
}

/// The *Signal R* mark from `brand/mark.svg`: a capital R on a 48 grid in round 4-unit strokes, its bowl sending two
/// spark waves. The R is the accent text color and the waves the spark color.
class RelayMark extends StatelessWidget {
  const RelayMark({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return Semantics(
      excludeSemantics: true,
      child: CustomPaint(size: Size.square(size), painter: RelayMarkPainter(ink: brand.accentText, spark: brand.spark)),
    );
  }
}

/// Paints [RelayMark]. The paths match `brand/mark.svg`.
class RelayMarkPainter extends CustomPainter {
  const RelayMarkPainter({required this.ink, required this.spark});

  final Color ink;
  final Color spark;

  /// The stem, the bowl and the leg: `M13 42V7`, `M13 7h11a8.5 8.5 0 0 1 0 17H13`, `M22 24l11 17`.
  static Path get letter => Path()
    ..moveTo(13, 42)..lineTo(13, 7)
    ..moveTo(13, 7)..lineTo(24, 7)..arcToPoint(const Offset(24, 24), radius: const Radius.circular(8.5))..lineTo(13, 24)
    ..moveTo(22, 24)..lineTo(33, 41);

  /// The two waves off the bowl: `M35.1 6.2a14.5 14.5 0 0 1 0 18.6`, `M39.7 2.3a20.5 20.5 0 0 1 0 26.4`.
  static Path get waves => Path()
    ..moveTo(35.1, 6.2)..arcToPoint(const Offset(35.1, 24.8), radius: const Radius.circular(14.5))
    ..moveTo(39.7, 2.3)..arcToPoint(const Offset(39.7, 28.7), radius: const Radius.circular(20.5));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(letter, stroke..color = ink);
    canvas.drawPath(waves, stroke..color = spark);
  }

  @override
  bool shouldRepaint(RelayMarkPainter old) => old.ink != ink || old.spark != spark;
}

/// Puts Inter's license (SIL Open Font License) on the app's licenses page.
void registerBrandLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [brandFont], await rootBundle.loadString('assets/fonts/inter/OFL.txt'));
  });
}

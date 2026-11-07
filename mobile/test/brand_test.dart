import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/brand.dart';

/// The WCAG contrast ratio of two colors, 1 to 21.
double contrast(Color a, Color b) {
  final (light, dark) = a.computeLuminance() > b.computeLuminance()
    ? (a.computeLuminance(), b.computeLuminance()) : (b.computeLuminance(), a.computeLuminance());
  return (light + 0.05) / (dark + 0.05);
}

/// Each text color the brand uses on each background it is used on (wiki/brand.md, design.md's readability check).
Map<String, (Color, Color)> textPairs(BrandColors c) => {
  'ink on paper': (c.ink, c.paper),
  'ink on card': (c.ink, c.card),
  'muted on paper': (c.muted, c.paper),
  'muted on card': (c.muted, c.card),
  'on-accent on accent': (c.onAccent, c.accent),
  'accent-text on paper': (c.accentText, c.paper),
  'accent-text on card': (c.accentText, c.card),
  'accent-text on accent-soft': (c.accentText, c.accentSoft),
  'on-spark on spark': (c.onSpark, c.spark),
  'danger on paper': (c.danger, c.paper),
  'danger on card': (c.danger, c.card),
  'on-danger on danger': (c.onDanger, c.danger),
};

/// Each Material text slot on the slot it sits on, so a widget that reads the scheme stays readable too.
Map<String, (Color, Color)> schemePairs(ColorScheme s) => {
  'onSurface on surface': (s.onSurface, s.surface),
  'onSurfaceVariant on surface': (s.onSurfaceVariant, s.surface),
  'onSurface on surfaceContainerHighest': (s.onSurface, s.surfaceContainerHighest),
  'onPrimary on primary': (s.onPrimary, s.primary),
  'onPrimaryContainer on primaryContainer': (s.onPrimaryContainer, s.primaryContainer),
  'onSecondary on secondary': (s.onSecondary, s.secondary),
  'onSecondaryContainer on secondaryContainer': (s.onSecondaryContainer, s.secondaryContainer),
  'onTertiary on tertiary': (s.onTertiary, s.tertiary),
  'onTertiaryContainer on tertiaryContainer': (s.onTertiaryContainer, s.tertiaryContainer),
  'onError on error': (s.onError, s.error),
  'onErrorContainer on errorContainer': (s.onErrorContainer, s.errorContainer),
  'onInverseSurface on inverseSurface': (s.onInverseSurface, s.inverseSurface),
  'inversePrimary on inverseSurface': (s.inversePrimary, s.inverseSurface),
};

/// The pairs under 4.5 to 1, named with their ratio.
List<String> unreadable(Map<String, (Color, Color)> pairs) => [
  for (final MapEntry(key: name, value: (text, back)) in pairs.entries)
    if (contrast(text, back) < 4.5) '$name: ${contrast(text, back).toStringAsFixed(2)} to 1',
];

void main() {
  test('the contrast check measures WCAG ratios', () {
    expect(contrast(Colors.black, Colors.white), closeTo(21, 0.01));
    expect(contrast(Colors.white, Colors.white), 1);
  });

  for (final brightness in Brightness.values) {
    group(brightness.name, () {
      final colors = BrandColors.of(brightness);
      final theme = brandTheme(brightness);

      test('every brand text color is at least 4.5 to 1 on its background', () {
        expect(unreadable(textPairs(colors)), isEmpty);
      });

      test('every Material text slot is at least 4.5 to 1 on its slot', () {
        expect(unreadable(schemePairs(theme.colorScheme)), isEmpty);
      });

      test('the theme is built from the brand set, not a seed', () {
        expect(theme.brightness, brightness);
        expect(theme.colorScheme.primary, colors.accent);
        expect(theme.colorScheme.surface, colors.paper);
        expect(theme.scaffoldBackgroundColor, colors.paper);
        expect(theme.cardTheme.color, colors.card);
        expect(theme.extension<BrandColors>(), colors);
      });

      test('uses Inter for every text style', () {
        final styles = [theme.textTheme.displayLarge, theme.textTheme.headlineSmall, theme.textTheme.titleLarge,
          theme.textTheme.titleMedium, theme.textTheme.bodyLarge, theme.textTheme.bodyMedium, theme.textTheme.bodySmall,
          theme.textTheme.labelLarge, theme.appBarTheme.titleTextStyle];
        for (final style in styles) {
          expect(style?.fontFamily, brandFont);
        }
      });
    });
  }

  test('a muted color too light for paper fails, and the failure names the pair', () {
    final pale = BrandColors.light.copyWith(muted: const Color(0xFF9AA39C));
    expect(unreadable(textPairs(pale)), [startsWith('muted on paper:'), startsWith('muted on card:')]);
  });

  test('the mark paints the R in accent text and the waves in spark', () {
    const painter = RelayMarkPainter(ink: Color(0xFF0E7A5A), spark: Color(0xFFF5A524));
    expect(RelayMarkPainter.letter.getBounds(), const Rect.fromLTRB(13, 7, 33, 42));
    expect(RelayMarkPainter.waves.computeMetrics().length, 2);
    expect(painter.shouldRepaint(const RelayMarkPainter(ink: Color(0xFF0E7A5A), spark: Color(0xFFF5A524))), isFalse);
    expect(painter.shouldRepaint(const RelayMarkPainter(ink: Color(0xFF4CC79A), spark: Color(0xFFF5A524))), isTrue);
  });

  testWidgets("Inter's license is on the licenses page", (tester) async {
    registerBrandLicenses();
    final licenses = await tester.runAsync(() => LicenseRegistry.licenses.toList());
    final inter = licenses!.where((license) => license.packages.contains(brandFont)).toList();
    expect(inter, hasLength(1));
    final text = inter.single.paragraphs.map((paragraph) => paragraph.text).join('\n');
    expect(text, contains('SIL Open Font License'));
  });
}

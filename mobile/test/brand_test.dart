import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/brand.dart';

import 'narrow_test.dart' show loadInter;

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

/// Each brand token by its name, as `Brand.swift` names it.
Map<String, Color> tokens(BrandColors c) => {
  'paper': c.paper, 'card': c.card, 'line': c.line, 'ink': c.ink, 'muted': c.muted, 'accent': c.accent,
  'onAccent': c.onAccent, 'accentText': c.accentText, 'accentSoft': c.accentSoft, 'spark': c.spark,
  'onSpark': c.onSpark, 'danger': c.danger, 'onDanger': c.onDanger,
};

/// The tokens where the share sheet's `Brand.swift` differs from [BrandColors], each named with both values.
List<String> swiftDrift(String swift) {
  final line = RegExp(r'static let (\w+) = color\(light: 0x([0-9A-Fa-f]{6}), dark: 0x([0-9A-Fa-f]{6})\)');
  final found = {
    for (final m in line.allMatches(swift)) m[1]!: ['0x${m[2]!.toUpperCase()}', '0x${m[3]!.toUpperCase()}'],
  };
  String hex(Color c) => '0x${(c.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';
  final names = tokens(BrandColors.light).keys;
  final sides = [('light', tokens(BrandColors.light)), ('dark', tokens(BrandColors.dark))];
  return [
    for (final name in names)
      for (final (i, (side, colors)) in sides.indexed)
        if (found[name]?[i] != hex(colors[name]!))
          '$name $side: Brand.swift has ${found[name]?[i] ?? 'none'}, BrandColors ${hex(colors[name]!)}',
    for (final name in found.keys) if (!names.contains(name)) '$name: in Brand.swift, not in BrandColors',
  ];
}

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
        // The app bars' titles take titleLarge and, large, headlineMedium.
        final styles = [theme.textTheme.displayLarge, theme.textTheme.headlineMedium, theme.textTheme.headlineSmall,
          theme.textTheme.titleLarge, theme.textTheme.titleMedium, theme.textTheme.bodyLarge, theme.textTheme.bodyMedium,
          theme.textTheme.bodySmall, theme.textTheme.labelLarge, theme.listTileTheme.titleTextStyle,
          theme.listTileTheme.subtitleTextStyle];
        for (final style in styles) {
          expect(style?.fontFamily, brandFont);
        }
      });
    });
  }

  test('the theme sets the brand scale: 16 px body, 13 px muted list help, 32 px large titles, flat cards, soft dialogs', () {
    final theme = brandTheme(Brightness.light);
    expect([theme.textTheme.bodyMedium?.fontSize, theme.listTileTheme.subtitleTextStyle?.fontSize,
      theme.listTileTheme.subtitleTextStyle?.color, theme.textTheme.headlineMedium?.fontSize,
      theme.textTheme.headlineMedium?.fontWeight, theme.cardTheme.margin, theme.appBarTheme.backgroundColor],
      [16, 13, BrandColors.light.muted, 32, FontWeight.w700, EdgeInsets.zero, BrandColors.light.paper]);
    expect((theme.dialogTheme.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(16));
  });

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

  test("the iPhone share sheet's Brand.swift has every BrandColors hex, light and dark", () {
    expect(swiftDrift(File('ios/ShareExtension/Brand.swift').readAsStringSync()), isEmpty);
  });

  test('a Swift hex that differs from BrandColors fails, and the failure names the token', () {
    final swift = File('ios/ShareExtension/Brand.swift').readAsStringSync()
      .replaceFirst('static let muted = color(light: 0x5E6660', 'static let muted = color(light: 0x9AA39C');
    expect(swiftDrift(swift), ['muted light: Brand.swift has 0x9AA39C, BrandColors 0x5E6660']);
  });

  testWidgets('a quiet button draws its words in Inter, not in a font the browser may not have', (tester) async {
    await loadInter();
    await tester.pumpWidget(MaterialApp(theme: brandTheme(Brightness.light), home: Scaffold(body: Builder(
      builder: (context) => Column(children: [
        for (final label in ['Copy', 'Sign out'])
          TextButton(onPressed: () {}, style: quietButton(context), child: Text(label)),
      ])))));
    for (final label in ['Copy', 'Sign out']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(paragraph.text.style?.fontFamily, brandFont, reason: label);
      // The test font draws each letter as a 15 px square; Inter's letters are narrower, so the words are Inter's.
      final width = paragraph.getMaxIntrinsicWidth(double.infinity);
      expect(width, greaterThan(0), reason: label);
      expect(width, lessThan(15.0 * label.length), reason: label);
    }
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

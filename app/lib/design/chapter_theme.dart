import 'package:flutter/material.dart';

enum ChapterWorld { welcome, lab, studio, adventure }

@immutable
class ChapterPalette extends ThemeExtension<ChapterPalette> {
  const ChapterPalette({
    required this.world,
    required this.label,
    required this.accent,
    required this.wash,
  });
  final ChapterWorld world;
  final String label;
  final Color accent;
  final Color wash;
  static const background = Color(0xFFFFF8F2);
  static const surface = Color(0xFFFFFEFC);
  static const ink = Color(0xFF342C29);
  static const muted = Color(0xFF74665D);
  static const primary = Color(0xFFB7472C);
  static const common = ChapterPalette(
    world: ChapterWorld.welcome,
    label: '学びを、創造へ。',
    accent: primary,
    wash: Color(0xFFFBE9DB),
  );
  static ChapterPalette forUnit(String unitId) => switch (unitId) {
    'u1' => const ChapterPalette(
      world: ChapterWorld.lab,
      label: '未来の学習ラボ',
      accent: Color(0xFFAE482F),
      wash: Color(0xFFFCE5DA),
    ),
    'u2' => const ChapterPalette(
      world: ChapterWorld.studio,
      label: 'AIの創作スタジオ',
      accent: Color(0xFF945414),
      wash: Color(0xFFFFEBCB),
    ),
    'u3' => const ChapterPalette(
      world: ChapterWorld.adventure,
      label: '冒険する学習ワールド',
      accent: Color(0xFF52663B),
      wash: Color(0xFFF0E7CF),
    ),
    _ => common,
  };
  static ChapterPalette of(BuildContext context) =>
      Theme.of(context).extension<ChapterPalette>() ?? common;
  @override
  ChapterPalette copyWith({
    ChapterWorld? world,
    String? label,
    Color? accent,
    Color? wash,
  }) => ChapterPalette(
    world: world ?? this.world,
    label: label ?? this.label,
    accent: accent ?? this.accent,
    wash: wash ?? this.wash,
  );
  @override
  ChapterPalette lerp(covariant ChapterPalette? other, double t) =>
      other == null
      ? this
      : ChapterPalette(
          world: t < .5 ? world : other.world,
          label: t < .5 ? label : other.label,
          accent: Color.lerp(accent, other.accent, t)!,
          wash: Color.lerp(wash, other.wash, t)!,
        );
}

ThemeData ailearnTheme([ChapterPalette palette = ChapterPalette.common]) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: palette.accent,
        brightness: Brightness.light,
      ).copyWith(
        primary: palette.accent,
        onPrimary: Colors.white,
        surface: ChapterPalette.surface,
        onSurface: ChapterPalette.ink,
        onSurfaceVariant: ChapterPalette.muted,
        primaryContainer: palette.wash,
        onPrimaryContainer: ChapterPalette.ink,
        outline: const Color(0xFF9A8475),
        outlineVariant: const Color(0xFFE6D8CD),
      );
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'WDXL Lubrifont JP N',
    colorScheme: scheme,
    scaffoldBackgroundColor: ChapterPalette.background,
    extensions: [palette],
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.65,
        color: ChapterPalette.ink,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 16,
        height: 1.6,
        color: ChapterPalette.ink,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 24,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: ChapterPalette.ink,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 32,
        height: 1.25,
        fontWeight: FontWeight.w800,
        color: ChapterPalette.ink,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: ChapterPalette.background,
      foregroundColor: ChapterPalette.ink,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: base.textTheme.labelLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: base.textTheme.labelLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ChapterPalette.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.all(18),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFE6D8CD)),
  );
}

class ChapterScope extends StatelessWidget {
  const ChapterScope({super.key, required this.palette, required this.child});
  final ChapterPalette palette;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Theme(data: ailearnTheme(palette), child: child);
}

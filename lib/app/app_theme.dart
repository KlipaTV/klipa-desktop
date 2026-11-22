import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

abstract final class KlipaColors {
  // Unified Klipa 0.10 Cinema Dark palette (shared across mobile, TV, desktop, web).
  static const ink = Color(0xFF0A0B0D);
  static const inkRaised = Color(0xFF131519);
  static const inkSurface = Color(0xFF1B1E24);
  static const inkHover = Color(0xFF242830);
  static const foreground = Color(0xFFF5F4F0);
  static const foregroundMuted = Color(0xFF9C9B96);
  static const foregroundDim = Color(0xFF8C8B86);

  /// Signature Klipa tally orange for live dots, focus rings and active accents.
  static const tally = Color(0xFFFF5B24);

  /// Darker tally fill for filled buttons/badges with white text (4.67:1 WCAG AA).
  static const tallyFill = Color(0xFFD43E0C);
  static const tallySoft = Color(0x24FF5B24);
  static const onTally = Color(0xFFFFFFFF);

  static const success = Color(0xFF3DDC97);
  static const warning = Color(0xFFFFC53D);
  static const live = tally;
  static const danger = Color(0xFFFF5A69);
  static const border = Color(0x17FFFFFF);
  static const borderStrong = Color(0x29FFFFFF);
}

abstract final class KlipaRadius {
  static const chip = 6.0;
  static const control = 12.0;
  static const card = 20.0;
}

ThemeData buildKlipaTheme() {
  const fontFallback = <String>[
    'Inter',
    'Segoe UI',
    'Ubuntu',
    'Cantarell',
    'Noto Sans',
    'sans-serif',
  ];
  const colorScheme = ColorScheme.dark(
    primary: KlipaColors.foreground,
    onPrimary: KlipaColors.ink,
    secondary: KlipaColors.foregroundMuted,
    onSecondary: KlipaColors.ink,
    surface: KlipaColors.ink,
    onSurface: KlipaColors.foreground,
    surfaceContainerHighest: KlipaColors.inkHover,
    outline: KlipaColors.borderStrong,
    error: KlipaColors.danger,
    onError: KlipaColors.onTally,
  );
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: KlipaColors.ink,
    fontFamily: 'Inter',
    fontFamilyFallback: fontFallback,
    dividerColor: KlipaColors.border,
    splashFactory: NoSplash.splashFactory,
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        color: KlipaColors.foreground,
        fontSize: 32,
        height: 1.12,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.9,
      ),
      headlineSmall: TextStyle(
        color: KlipaColors.foreground,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleMedium: TextStyle(
        color: KlipaColors.foreground,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: TextStyle(color: KlipaColors.foregroundMuted, height: 1.45),
      bodySmall: TextStyle(color: KlipaColors.foregroundDim, height: 1.4),
      labelLarge: TextStyle(fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: KlipaColors.inkRaised,
      hintStyle: const TextStyle(color: KlipaColors.foregroundDim),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KlipaRadius.control),
        borderSide: const BorderSide(color: KlipaColors.borderStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KlipaRadius.control),
        borderSide: const BorderSide(color: KlipaColors.borderStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KlipaRadius.control),
        borderSide: const BorderSide(color: KlipaColors.tally, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: KlipaColors.tallyFill,
        foregroundColor: KlipaColors.onTally,
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KlipaRadius.control),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: KlipaColors.foreground,
        minimumSize: const Size(0, 44),
        side: const BorderSide(color: KlipaColors.borderStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KlipaRadius.control),
        ),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: KlipaColors.tally,
      inactiveTrackColor: KlipaColors.borderStrong,
      thumbColor: KlipaColors.foreground,
      overlayColor: KlipaColors.tallySoft,
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: KlipaColors.inkRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KlipaRadius.card),
        side: const BorderSide(color: KlipaColors.borderStrong),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: KlipaColors.inkHover,
        borderRadius: BorderRadius.circular(KlipaRadius.chip),
        border: Border.all(color: KlipaColors.borderStrong),
      ),
      textStyle: const TextStyle(color: KlipaColors.foreground, fontSize: 12),
    ),
  );
}

/// Calm 3-bar signal pulse replacing generic Material spinning circles.
class DesktopTallyLoader extends StatefulWidget {
  const DesktopTallyLoader({
    super.key,
    this.size = 20,
    this.color = KlipaColors.tally,
  });

  final double size;
  final Color color;

  @override
  State<DesktopTallyLoader> createState() => _DesktopTallyLoaderState();
}

class _DesktopTallyLoaderState extends State<DesktopTallyLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduced) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      unawaited(_controller.repeat());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barW = (widget.size * 0.19).clamp(2.2, 4.5);
    final gap = (widget.size * 0.14).clamp(1.8, 4.0);
    Widget bars(double t) => SizedBox(
      width: widget.size,
      height: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Builder(
              builder: (_) {
                final wave = _reduced
                    ? (i == 1 ? 0.85 : 0.48)
                    : 0.34 +
                          0.66 *
                              (0.5 +
                                  0.5 * math.sin(t * 2 * math.pi - i * 1.05));
                return Container(
                  width: barW,
                  height: (widget.size * 0.84 * wave).clamp(barW, widget.size),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.45 + 0.55 * wave),
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
    return ExcludeSemantics(
      child: _reduced
          ? bars(0)
          : AnimatedBuilder(
              animation: _controller,
              builder: (_, _) => bars(_controller.value),
            ),
    );
  }
}

/// Smooth left-to-right skeleton sheen for desktop loading states.
class DesktopSkeletonSheen extends StatefulWidget {
  const DesktopSkeletonSheen({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopSkeletonSheen> createState() => _DesktopSkeletonSheenState();
}

class _DesktopSkeletonSheenState extends State<DesktopSkeletonSheen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduced) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      unawaited(_controller.repeat());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = ExcludeSemantics(child: widget.child);
    if (_reduced) return child;
    const base = KlipaColors.inkSurface;
    const highlight = Color(0xFF282D37);
    return AnimatedBuilder(
      animation: _controller,
      child: child,
      builder: (_, child) {
        final travel = -0.6 + 1.8 * _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [base, highlight, base],
            stops: [
              (travel - 0.2).clamp(0.0, 1.0),
              travel.clamp(0.0, 1.0),
              (travel + 0.2).clamp(0.0, 1.0),
            ],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

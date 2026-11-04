import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'state.dart';
import 'strings.dart';

/// One design system for the app and the web panel, following Apple's Human Interface
/// Guidelines: the system font (SF Pro on Apple devices), iOS semantic colours, grouped inset
/// lists, continuous (squircle) corners, translucent bars and spring motion that respects
/// Reduce Motion. The couple's names keep a serif, as on a printed invitation.
class Brand {
  // iOS semantic colours (light appearance).
  static const paper = Color(0xFFF2F2F7); // systemGroupedBackground
  static const surface = Color(0xFFFFFFFF); // secondarySystemGroupedBackground
  static const sunk = Color(0xFFE9E9EE); // tertiarySystemFill on white
  static const line = Color(0xFFD8D8DD); // separator
  static const ink = Color(0xFF000000); // label
  static const ink2 = Color(0xFF6E6E73); // secondaryLabel, darkened for contrast
  static const ink3 = Color(0xFFAEAEB2); // tertiaryLabel
  static const night = Color(0xFF1C1C1E); // secondarySystemBackground (dark)

  /// The app's tint: a rose that reads on white (4.6:1) and on the dark cards.
  static const accent = Color(0xFFD7305A);
  static const accentSoft = Color(0xFFFBE4EA);

  // System colours used for icons and status.
  static const pink = Color(0xFFFF2D55);
  static const orange = Color(0xFFFF9500);
  static const yellow = Color(0xFFFFCC00);
  static const green = Color(0xFF34C759);
  static const teal = Color(0xFF30B0C7);
  static const blue = Color(0xFF007AFF);
  static const indigo = Color(0xFF5856D6);
  static const purple = Color(0xFFAF52DE);
  static const gray = Color(0xFF8E8E93);

  // Accessible text variants of status colours.
  static const gold = Color(0xFFB25000);
  static const success = Color(0xFF248A3D);
  static const warn = Color(0xFFC93400);

  // Activity-ring colours, from Apple Fitness.
  static const ringMove = Color(0xFFFA114F);
  static const ringExercise = Color(0xFF92E82A);
  static const ringStand = Color(0xFF1EEAEF);

  static const cream = paper;

  /// SF Pro Display / Text on Apple platforms; other platforms fall back to their own font.
  static const sans = 'CupertinoSystemText';
  static const sansDisplay = 'CupertinoSystemDisplay';
  static const serif = 'Instrument Serif';

  /// Bold display type for titles and big numbers, tracked tighter as it grows.
  static TextStyle display(double size, {Color color = ink, FontWeight weight = FontWeight.w700, FontStyle? style}) => TextStyle(
        fontFamily: sansDisplay,
        fontSize: size,
        height: 1.08,
        letterSpacing: size >= 24 ? -0.022 * size : -0.2,
        color: color,
        fontWeight: weight,
        fontStyle: style,
      );

  /// The invitation serif, for the couple's names.
  static TextStyle serifDisplay(double size, {Color color = ink, FontStyle? style}) =>
      TextStyle(fontFamily: serif, fontSize: size, height: 1.0, letterSpacing: -0.4, color: color, fontStyle: style);

  /// True when the person asked the system to reduce motion; animations then become fades or stop.
  static bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static ShapeBorder squircle(double r, {BorderSide side = BorderSide.none}) => RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(r), side: side);

  static ThemeData theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: b).copyWith(
      primary: accent,
      onPrimary: Colors.white,
      primaryContainer: accentSoft,
      onPrimaryContainer: accent,
      secondary: indigo,
      secondaryContainer: sunk,
      onSecondaryContainer: ink,
      tertiary: orange,
      tertiaryContainer: const Color(0xFFFFF1DC),
      onTertiaryContainer: ink,
      error: const Color(0xFFD70015),
      errorContainer: const Color(0xFFFFE5E7),
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: ink2,
      surfaceContainerLowest: surface,
      surfaceContainerLow: surface,
      surfaceContainer: paper,
      surfaceContainerHigh: sunk,
      surfaceContainerHighest: sunk,
      outline: gray,
      outlineVariant: line,
    );
    TextStyle t(double size, FontWeight w, double spacing, {Color color = ink, double height = 1.3, String family = sans}) =>
        TextStyle(fontFamily: family, fontSize: size, fontWeight: w, letterSpacing: spacing, color: color, height: height);
    // Apple's text styles: Large Title 34, Title 1 28, Title 2 22, Title 3 20, Headline 17,
    // Body 17, Callout 16, Subheadline 15, Footnote 13, Caption 12. Body stays 17 for elders.
    final text = TextTheme(
      displayLarge: display(56),
      displayMedium: display(44),
      displaySmall: display(38),
      headlineLarge: display(34),
      headlineMedium: display(28),
      headlineSmall: display(22),
      titleLarge: t(20, FontWeight.w700, -0.45, family: sansDisplay),
      titleMedium: t(17, FontWeight.w600, -0.43),
      titleSmall: t(15, FontWeight.w600, -0.23),
      bodyLarge: t(17, FontWeight.w400, -0.43, height: 1.4),
      bodyMedium: t(17, FontWeight.w400, -0.43, height: 1.4),
      bodySmall: t(13, FontWeight.w400, -0.08, color: ink2),
      labelLarge: t(17, FontWeight.w600, -0.43),
      labelMedium: t(13, FontWeight.w500, -0.08, color: ink2),
      labelSmall: t(12, FontWeight.w500, 0, color: ink2),
    );
    final r12 = BorderRadius.circular(12);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: sans,
      textTheme: text,
      scaffoldBackgroundColor: paper,
      canvasColor: paper,
      dividerColor: line,
      // No Material ripples: Apple controls highlight or scale when pressed.
      splashFactory: NoSplash.splashFactory,
      highlightColor: ink.withValues(alpha: 0.05),
      hoverColor: ink.withValues(alpha: 0.03),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
      }),
      cupertinoOverrideTheme: const CupertinoThemeData(
        primaryColor: accent,
        scaffoldBackgroundColor: paper,
        barBackgroundColor: Color(0xCCF2F2F7),
        textTheme: CupertinoTextThemeData(primaryColor: accent),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: paper.withValues(alpha: 0.94),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 52,
        foregroundColor: accent,
        iconTheme: const IconThemeData(color: accent),
        actionsIconTheme: const IconThemeData(color: accent),
        titleTextStyle: t(17, FontWeight.w600, -0.43),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: sunk,
          disabledForegroundColor: ink3,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: const StadiumBorder(),
          elevation: 0,
          textStyle: t(17, FontWeight.w600, -0.43),
        ),
      ),
      // Outlined buttons are drawn as Apple's tinted ("bordered") buttons.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          backgroundColor: accent.withValues(alpha: 0.11),
          disabledForegroundColor: ink3,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          side: BorderSide.none,
          shape: const StadiumBorder(),
          textStyle: t(16, FontWeight.w600, -0.31),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(44, 44),
          shape: const StadiumBorder(),
          textStyle: t(17, FontWeight.w400, -0.43),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: accent)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: t(17, FontWeight.w400, -0.43, color: ink2),
        floatingLabelStyle: t(15, FontWeight.w600, -0.23, color: accent),
        hintStyle: t(17, FontWeight.w400, -0.43, color: ink3),
        prefixIconColor: ink2,
        border: OutlineInputBorder(borderRadius: r12, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: r12, borderSide: BorderSide.none),
        disabledBorder: OutlineInputBorder(borderRadius: r12, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: r12, borderSide: const BorderSide(color: accent, width: 1.6)),
        errorBorder: OutlineInputBorder(borderRadius: r12, borderSide: const BorderSide(color: Color(0xFFD70015))),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 5),
        shape: squircle(22),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: accent,
        titleTextStyle: t(17, FontWeight.w400, -0.43),
        subtitleTextStyle: t(15, FontWeight.w400, -0.23, color: ink2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: ink,
        disabledColor: sunk,
        showCheckmark: false,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        // Unselected chips use labelStyle, selected ones secondaryLabelStyle.
        labelStyle: t(15, FontWeight.w600, -0.23),
        secondaryLabelStyle: t(15, FontWeight.w600, -0.23, color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? surface : sunk),
          foregroundColor: const WidgetStatePropertyAll(ink),
          side: const WidgetStatePropertyAll(BorderSide(color: sunk, width: 2)),
          textStyle: WidgetStatePropertyAll(t(15, FontWeight.w600, -0.23)),
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? green : sunk),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? accent : Colors.transparent),
        side: const BorderSide(color: ink3, width: 1.5),
        shape: const CircleBorder(),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? accent : ink3)),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent, linearTrackColor: sunk, circularTrackColor: sunk),
      dividerTheme: const DividerThemeData(color: line, thickness: 0.5, space: 0.5),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: Color(0xFFC7C7CC),
        dragHandleSize: Size(36, 5),
        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: squircle(26),
        titleTextStyle: t(20, FontWeight.w700, -0.45, family: sansDisplay),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface.withValues(alpha: 0.97),
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: ink.withValues(alpha: 0.18),
        shape: squircle(16),
        textStyle: t(17, FontWeight.w400, -0.43),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: night.withValues(alpha: 0.94),
        contentTextStyle: t(15, FontWeight.w600, -0.23, color: Colors.white),
        shape: squircle(18),
        elevation: 0,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: ink2,
        indicatorColor: accent,
        dividerColor: line,
        labelStyle: t(15, FontWeight.w600, -0.23),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: paper,
        indicatorColor: accentSoft,
        selectedIconTheme: const IconThemeData(color: accent),
        unselectedIconTheme: const IconThemeData(color: gray),
        selectedLabelTextStyle: t(13, FontWeight.w600, -0.08, color: accent),
        unselectedLabelTextStyle: t(13, FontWeight.w500, -0.08, color: ink2),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: accent, foregroundColor: Colors.white, shape: StadiumBorder(), elevation: 2),
      expansionTileTheme: const ExpansionTileThemeData(shape: Border(), collapsedShape: Border()),
      datePickerTheme: DatePickerThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent, shape: squircle(26)),
      timePickerTheme: TimePickerThemeData(backgroundColor: surface, shape: squircle(26)),
    );
  }
}

/// Short-hand for translated text from the current locale.
extension Tr on AppState {
  String t(String key, [Map<String, Object>? vars]) => tr(locale, key, vars);
}

/// What the main shell puts in every tab's navigation bar (the account button, a back button
/// for planners), so each tab can show its own large title.
class ShellChrome extends InheritedWidget {
  const ShellChrome({super.key, this.leading, this.trailing, required super.child});
  final Widget? leading, trailing;
  static ShellChrome? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellChrome>();
  @override
  bool updateShouldNotify(ShellChrome old) => old.leading != leading || old.trailing != trailing;
}

/// A scrolling page. With a [title] it gets an iOS large title that shrinks into a translucent
/// bar as you scroll; with [onRefresh], pull-to-refresh. Children fade and rise in, one after
/// another, the first time the page appears. The column stays readable on wide web screens.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.children,
    this.maxWidth = 720,
    this.padding = const EdgeInsets.all(16),
    this.title,
    this.leading,
    this.trailing,
    this.onRefresh,
    this.reveal = true,
  });
  final List<Widget> children;
  final double maxWidth;
  final EdgeInsets padding;
  final String? title;
  final Widget? leading, trailing;
  final Future<void> Function()? onRefresh;
  final bool reveal;

  @override
  Widget build(BuildContext context) {
    final chrome = ShellChrome.maybeOf(context);
    final lead = leading ?? chrome?.leading;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        if (title != null)
          CupertinoSliverNavigationBar(
            largeTitle: Text(title!),
            leading: lead,
            automaticallyImplyLeading: lead == null,
            trailing: trailing ?? chrome?.trailing,
            transitionBetweenRoutes: false,
            backgroundColor: Brand.paper.withValues(alpha: 0.82),
            border: const Border(bottom: BorderSide(color: Brand.line, width: 0.5)),
          ),
        if (onRefresh != null) CupertinoSliverRefreshControl(onRefresh: onRefresh),
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding: padding,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var i = 0; i < children.length; i++) reveal ? Reveal(index: i, child: children[i]) : children[i],
                ]),
              ),
            ),
          ),
        ),
        // Room for the floating tab bar, which the page scrolls behind.
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom)),
      ],
    );
  }
}

/// Fades and lifts a child into place, a little after the one before it.
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.child, this.index = 0, this.offset = 0.06});
  final Widget child;
  final int index;
  final double offset;
  @override
  Widget build(BuildContext context) {
    if (Brand.reduceMotion(context)) return child;
    final delay = Duration(milliseconds: 40 + 55 * math.min(index, 10));
    return child
        .animate(delay: delay)
        .fadeIn(duration: 420.ms, curve: Curves.easeOutCubic)
        .slideY(begin: offset, end: 0, duration: 520.ms, curve: Curves.easeOutQuart)
        .scaleXY(begin: 0.985, end: 1, duration: 520.ms, curve: Curves.easeOutQuart);
  }
}

/// Shrinks a little while pressed and springs back, with a light tap of haptics.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.965, this.haptic = true});
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool down = false;
  void set(bool v) {
    if (widget.onTap != null && down != v) setState(() => down = v);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => set(true),
        onTapUp: (_) => set(false),
        onTapCancel: () => set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.lightImpact();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: down ? widget.scale : 1,
          duration: Duration(milliseconds: down ? 110 : 420),
          curve: down ? Curves.easeOut : Curves.elasticOut,
          child: widget.child,
        ),
      );
}

/// Every empty screen says what to do next, with one button (Apple's "content unavailable").
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.body, required this.action, required this.onAction});
  final IconData icon;
  final String title, body, action;
  final VoidCallback onAction;
  @override
  Widget build(BuildContext context) {
    Widget glyph = Container(
      width: 96,
      height: 96,
      decoration: const ShapeDecoration(
        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.all(Radius.circular(30))),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF6B8B), Brand.accent]),
      ),
      child: Icon(icon, size: 44, color: Colors.white),
    );
    if (!Brand.reduceMotion(context)) {
      glyph = glyph.animate().scaleXY(begin: 0.6, end: 1, duration: 650.ms, curve: Curves.elasticOut).fadeIn(duration: 250.ms);
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            glyph,
            const SizedBox(height: 24),
            Reveal(index: 1, child: Text(title, style: Brand.display(26), textAlign: TextAlign.center)),
            const SizedBox(height: 10),
            Reveal(index: 2, child: Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Brand.ink2))),
            const SizedBox(height: 28),
            Reveal(index: 3, child: FilledButton(onPressed: onAction, child: Text(action))),
          ]),
        ),
      ),
    );
  }
}

/// A number that counts up to its value when it first appears or changes.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount(this.value, {super.key, required this.style, this.prefix = '', this.suffix = ''});
  final num value;
  final TextStyle style;
  final String prefix, suffix;
  @override
  Widget build(BuildContext context) {
    final text = Text('$prefix${value.round()}$suffix', style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]));
    if (Brand.reduceMotion(context)) return text;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutExpo,
      builder: (_, v, _) => Text('$prefix${v.round()}$suffix', style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }
}

/// Summary tiles in rows of [cols], each its own card, like Apple Health's highlights. Each row
/// is as tall as its tallest tile, so a label never clips on a narrow phone or with larger text.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.cols, required this.children});
  final int cols;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < children.length; i += cols)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
                for (var j = i; j < i + cols; j++) Expanded(child: j < children.length ? children[j] : const SizedBox()),
              ]),
            ),
          ),
      ]);
}

class StatTile extends StatelessWidget {
  const StatTile(this.label, this.value, {super.key, this.color, this.icon});
  final String label;
  final Object value;
  final Color? color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final tint = color ?? Brand.accent;
    final style = Brand.display(34, color: color == null ? Brand.ink : tint);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: ShapeDecoration(color: Brand.surface, shape: Brand.squircle(22)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 15, color: tint), const SizedBox(width: 5)],
              Flexible(child: Text(label, maxLines: 2, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tint, letterSpacing: -0.23))),
            ]),
            const Spacer(),
            const SizedBox(height: 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: value is num ? AnimatedCount(value as num, style: style) : Text('$value', maxLines: 1, style: style),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Small label above a title or under a number (Apple's footnote style).
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(fontFamily: Brand.sans, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: color ?? Brand.ink2, height: 1.2),
      );
}

/// A section title in Apple's Title 2 / Title 3 style, with an optional line above and an
/// optional action ("See all") on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.eyebrow, this.trailing, this.size = 22, this.padding = const EdgeInsets.fromLTRB(4, 26, 4, 10)});
  final String title;
  final String? eyebrow;
  final Widget? trailing;
  final double size;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (eyebrow != null) ...[Eyebrow(eyebrow!, color: Brand.accent), const SizedBox(height: 4)],
              Semantics(header: true, child: Text(title, style: Brand.display(size))),
            ]),
          ),
          ?trailing,
        ]),
      );
}

/// The basic surface: a white card with continuous corners on the grouped background. Tappable
/// cards shrink a little when pressed.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.onTap, this.color, this.borderColor, this.radius = 24, this.margin = const EdgeInsets.symmetric(vertical: 6), this.gradient});
  final Widget child;
  final EdgeInsets padding, margin;
  final VoidCallback? onTap;
  final Color? color, borderColor;
  final double radius;
  final Gradient? gradient;
  @override
  Widget build(BuildContext context) {
    final card = DecoratedBox(
      decoration: ShapeDecoration(
        color: gradient == null ? (color ?? Brand.surface) : null,
        gradient: gradient,
        shape: Brand.squircle(radius, side: borderColor == null ? BorderSide.none : BorderSide(color: borderColor!, width: 0.6)),
      ),
      child: Padding(padding: padding, child: child),
    );
    return Padding(
      padding: margin,
      child: onTap == null ? card : Semantics(button: true, child: Pressable(onTap: onTap, child: card)),
    );
  }
}

/// A row in an inset grouped list, as in Settings: a coloured rounded-square icon, a title, an
/// optional line of detail and a chevron (or whatever [trailing] gives).
class ActionRow extends StatelessWidget {
  const ActionRow({super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.trailing, this.tint});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? tint;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              IconTile(icon, tint: tint, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: const TextStyle(fontSize: 17, letterSpacing: -0.43, height: 1.25)),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: const TextStyle(fontSize: 15, color: Brand.ink2, height: 1.3, letterSpacing: -0.23)),
                  ],
                ]),
              ),
              const SizedBox(width: 8),
              trailing ?? (onTap == null ? const SizedBox.shrink() : const Icon(CupertinoIcons.chevron_forward, size: 17, color: Brand.ink3)),
            ]),
          ),
        ),
      );
}

/// Rows in one inset grouped section, ruled between them from the text edge, with an optional
/// header and footer as in Settings.
class RowGroup extends StatelessWidget {
  const RowGroup({super.key, required this.children, this.header, this.footer, this.indent = 62});
  final List<Widget> children;
  final String? header, footer;
  final double indent;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (header != null)
          Padding(padding: const EdgeInsets.fromLTRB(16, 18, 16, 7), child: Eyebrow(header!)),
        Panel(
          padding: EdgeInsets.zero,
          radius: 22,
          child: ClipRSuperellipse(
            borderRadius: BorderRadius.circular(22),
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: [
                for (var i = 0; i < children.length; i++) ...[if (i > 0) Divider(indent: indent), children[i]],
              ]),
            ),
          ),
        ),
        if (footer != null)
          Padding(padding: const EdgeInsets.fromLTRB(16, 2, 16, 6), child: Text(footer!, style: const TextStyle(fontSize: 13, color: Brand.ink2, height: 1.35))),
      ]);
}

/// The coloured rounded-square icon used in grouped lists and tiles (white glyph on colour).
/// Without a [tint] it is a quiet grey glyph on a light fill.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.tint, this.size = 44});
  final IconData icon;
  final Color? tint;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = tint;
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        shape: Brand.squircle(size * 0.28),
        color: c == null ? Brand.sunk : null,
        gradient: c == null ? null : LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(c, Colors.white, 0.18)!, c]),
      ),
      child: Icon(icon, size: size * 0.56, color: c == null ? Brand.ink2 : Colors.white),
    );
  }
}

/// Initials in a circle, as in Contacts; the gradient comes from the name, so the same guest
/// always looks the same.
class Monogram extends StatelessWidget {
  const Monogram(this.name, {super.key, this.size = 42});
  final String name;
  final double size;
  static const _tints = [
    [Color(0xFFFF8BA7), Color(0xFFE5486C)],
    [Color(0xFFFFB86B), Color(0xFFF2852C)],
    [Color(0xFF8FD4A0), Color(0xFF3DAE62)],
    [Color(0xFF8AB8FF), Color(0xFF3F7FE8)],
    [Color(0xFFB9A3FF), Color(0xFF7B5CE6)],
    [Color(0xFFA9B0BC), Color(0xFF7C8492)],
    [Color(0xFF7FD6E3), Color(0xFF2EA7BC)],
  ];
  @override
  Widget build(BuildContext context) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = words.isEmpty ? '?' : (words.length == 1 ? words.first.characters.first : '${words.first.characters.first}${words.last.characters.first}').toUpperCase();
    final g = _tints[name.hashCode.abs() % _tints.length];
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: g)),
        child: Text(initials, style: TextStyle(fontFamily: Brand.sansDisplay, fontSize: size * 0.4, fontWeight: FontWeight.w600, color: Colors.white, height: 1)),
      ),
    );
  }
}

/// A short status label in a tinted capsule.
class StatusTag extends StatelessWidget {
  const StatusTag(this.label, this.color, {super.key, this.filled = false});
  final String label;
  final Color color;
  final bool filled;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: filled ? 0.18 : 0.12), borderRadius: BorderRadius.circular(99)),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color, letterSpacing: -0.08)),
      );
}

/// A short ornament: a hairline with a small diamond in the middle.
class Flourish extends StatelessWidget {
  const Flourish({super.key, this.color = Brand.accent, this.width = 120});
  final Color color;
  final double width;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          width: width,
          child: Row(children: [
            Expanded(child: Container(height: 1, color: color.withValues(alpha: 0.5))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Transform.rotate(angle: 0.785, child: Container(width: 6, height: 6, color: color))),
            Expanded(child: Container(height: 1, color: color.withValues(alpha: 0.5))),
          ]),
        ),
      );
}

/// Couple names set as a pair in the invitation serif, the ampersand in italic.
class CoupleNames extends StatelessWidget {
  const CoupleNames(this.a, this.b, {super.key, this.size = 44, this.color = Brand.ink, this.amp = Brand.accent, this.align = TextAlign.start});
  final String a, b;
  final double size;
  final Color color, amp;
  final TextAlign align;
  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        label: '$a and $b',
        excludeSemantics: true,
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: a),
            TextSpan(text: ' & ', style: TextStyle(fontStyle: FontStyle.italic, color: amp)),
            TextSpan(text: b),
          ]),
          textAlign: align,
          style: Brand.serifDisplay(size, color: color),
        ),
      );
}

/// Frosted glass: whatever is behind shows through blurred, with a fine bright edge.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.radius = 26, this.dark = false, this.padding = EdgeInsets.zero, this.blur = 24, this.opacity});
  final Widget child;
  final double radius, blur;
  final bool dark;
  final EdgeInsets padding;
  final double? opacity;
  @override
  Widget build(BuildContext context) => ClipRSuperellipse(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: dark ? Colors.black.withValues(alpha: opacity ?? 0.32) : Colors.white.withValues(alpha: opacity ?? 0.72),
              shape: Brand.squircle(radius, side: BorderSide(color: Colors.white.withValues(alpha: dark ? 0.16 : 0.7), width: 0.8)),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
}

/// Phone navigation: a floating glass tab bar. Every tab shows its symbol and name; a tinted
/// capsule springs across to the open one.
class DockNav extends StatelessWidget {
  const DockNav({super.key, required this.items, required this.index, required this.onTap});
  final List<(String, IconData)> items;
  final int index;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final reduce = Brand.reduceMotion(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, bottom > 0 ? bottom - 6 : 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 30, offset: const Offset(0, 10))],
        ),
        child: Glass(
          radius: 34,
          opacity: 0.78,
          padding: const EdgeInsets.all(5),
          child: SizedBox(
            height: 58,
            child: LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth / items.length;
              return Stack(children: [
                AnimatedPositioned(
                  duration: reduce ? Duration.zero : const Duration(milliseconds: 460),
                  curve: Curves.easeOutBack,
                  left: w * index,
                  top: 0,
                  bottom: 0,
                  width: w,
                  child: DecoratedBox(decoration: BoxDecoration(color: Brand.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99))),
                ),
                Row(children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == index,
                        label: items[i].$1,
                        excludeSemantics: true,
                        child: Pressable(
                          scale: 0.88,
                          haptic: false,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onTap(i);
                          },
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            AnimatedScale(
                              scale: i == index ? 1.08 : 1,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutBack,
                              child: Icon(items[i].$2, size: 23, color: i == index ? Brand.accent : Brand.ink),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              items[i].$1,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: i == index ? Brand.accent : Brand.ink),
                            ),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

/// A capsule bar split into coloured parts (e.g. coming / maybe / not coming / no reply) that
/// grows in from the left.
class SplitBar extends StatelessWidget {
  const SplitBar({super.key, required this.parts, this.height = 10});
  final List<(num, Color)> parts;
  final double height;
  @override
  Widget build(BuildContext context) {
    final total = parts.fold<num>(0, (a, p) => a + p.$1);
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: height,
        child: total == 0
            ? Container(color: Brand.sunk)
            : Row(spacing: 2, children: [
                for (final p in parts)
                  if (p.$1 > 0) Expanded(flex: (p.$1 * 1000 ~/ total).clamp(1, 1000), child: Container(color: p.$2)),
              ]),
      ),
    );
    if (Brand.reduceMotion(context)) return bar;
    return bar.animate().scaleX(begin: 0, end: 1, alignment: Alignment.centerLeft, duration: 900.ms, delay: 200.ms, curve: Curves.easeOutQuart);
  }
}

/// Concentric progress rings, like Apple Fitness. They sweep round to their values.
class ActivityRings extends StatelessWidget {
  const ActivityRings({super.key, required this.values, this.colors = const [Brand.ringMove, Brand.ringExercise, Brand.ringStand], this.size = 132, this.stroke = 15});
  final List<double> values;
  final List<Color> colors;
  final double size, stroke;
  @override
  Widget build(BuildContext context) {
    Widget paint(double t) => CustomPaint(size: Size.square(size), painter: _RingsPainter([for (final v in values) v.clamp(0, 1) * t], colors, stroke));
    if (Brand.reduceMotion(context)) return paint(1);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeOutCubic,
      builder: (_, t, _) => paint(t),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.values, this.colors, this.stroke);
  final List<double> values;
  final List<Color> colors;
  final double stroke;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < values.length; i++) {
      final r = size.width / 2 - stroke / 2 - i * (stroke + 3);
      final rect = Rect.fromCircle(center: c, radius: r);
      final base = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = colors[i].withValues(alpha: 0.22);
      canvas.drawCircle(c, r, base);
      if (values[i] <= 0) continue;
      final sweep = 2 * math.pi * values[i];
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.max(sweep, 0.01),
          colors: [Color.lerp(colors[i], Colors.black, 0.12)!, colors[i]],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect);
      canvas.drawArc(rect, -math.pi / 2, sweep, false, arc);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.values != values;
}

/// A slowly drifting mesh of soft colour, used behind the sign-in, the home card when there is
/// no photo, and the Wedding Pass. Still when Reduce Motion is on.
class MeshBackdrop extends StatefulWidget {
  const MeshBackdrop({super.key, this.colors = const [Color(0xFFFF5E87), Color(0xFFFF9F68), Color(0xFF8E6CFF), Color(0xFF2A1B3D)], this.base = const Color(0xFF1A1020)});
  final List<Color> colors;
  final Color base;
  @override
  State<MeshBackdrop> createState() => _MeshBackdropState();
}

class _MeshBackdropState extends State<MeshBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 18));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Brand.reduceMotion(context)) {
      c.stop();
    } else if (!c.isAnimating) {
      c.repeat();
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: c,
            builder: (_, _) => CustomPaint(painter: _MeshPainter(c.value * 2 * math.pi, widget.colors, widget.base), child: const SizedBox.expand()),
          ),
        ),
      );
}

class _MeshPainter extends CustomPainter {
  _MeshPainter(this.t, this.colors, this.base);
  final double t;
  final List<Color> colors;
  final Color base;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final m = math.max(size.width, size.height);
    final spots = [
      (Offset(0.15 + 0.12 * math.sin(t), 0.15 + 0.10 * math.cos(t * 1.3)), 0.75),
      (Offset(0.88 + 0.10 * math.cos(t * 0.8), 0.28 + 0.14 * math.sin(t * 1.1)), 0.70),
      (Offset(0.30 + 0.16 * math.cos(t * 1.2), 0.85 + 0.08 * math.sin(t * 0.9)), 0.80),
      (Offset(0.80 + 0.12 * math.sin(t * 0.7), 0.95 + 0.06 * math.cos(t)), 0.65),
    ];
    for (var i = 0; i < spots.length && i < colors.length; i++) {
      final center = Offset(spots[i].$1.dx * size.width, spots[i].$1.dy * size.height);
      final r = m * spots[i].$2;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(colors: [colors[i].withValues(alpha: 0.85), colors[i].withValues(alpha: 0)]).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_MeshPainter old) => old.t != t;
}

/// A grey placeholder with a light sweeping across it while content loads.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.height = 64, this.radius = 22, this.width});
  final double height, radius;
  final double? width;
  @override
  Widget build(BuildContext context) {
    final box = Container(
      height: height,
      width: width,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: ShapeDecoration(color: Brand.sunk, shape: Brand.squircle(radius)),
    );
    if (Brand.reduceMotion(context)) return box;
    return box.animate(onPlay: (c) => c.repeat()).shimmer(duration: 1300.ms, color: Colors.white.withValues(alpha: 0.7));
  }
}

/// A page of placeholders shaped like the content that is coming.
class LoadingList extends StatelessWidget {
  const LoadingList({super.key, this.count = 5});
  final int count;
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const Skeleton(height: 34, width: 180, radius: 10),
          const SizedBox(height: 10),
          const Skeleton(height: 120),
          for (var i = 0; i < count; i++) const Skeleton(height: 62),
        ],
      );
}

/// Shown while the app is working from the copy saved on this phone.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.at, required this.onRetry});
  final DateTime at;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final local = at.toLocal();
    final time = '${local.day} ${_months[local.month - 1]}, ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: DecoratedBox(
        decoration: ShapeDecoration(color: Brand.night, shape: Brand.squircle(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
          child: Row(children: [
            const Icon(CupertinoIcons.wifi_slash, color: Colors.white, size: 19),
            const SizedBox(width: 12),
            Expanded(child: Semantics(liveRegion: true, child: Text(s.t('offlineCopy', {'time': time}), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)))),
            TextButton(onPressed: onRetry, style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF8FAB)), child: Text(s.t('retry'))),
          ]),
        ),
      ),
    );
  }
}

/// iOS-style sliding segmented control for a handful of choices.
class Segmented<T extends Object> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.options, this.onChanged});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T>? onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: CupertinoSlidingSegmentedControl<T>(
          groupValue: value,
          backgroundColor: const Color(0x1F767680),
          thumbColor: Brand.surface,
          padding: const EdgeInsets.all(3),
          onValueChanged: (v) {
            if (v == null || onChanged == null) return;
            HapticFeedback.selectionClick();
            onChanged!(v);
          },
          children: {
            for (final o in options)
              o.$1: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Text(o.$2, style: TextStyle(fontSize: 15, fontWeight: o.$1 == value ? FontWeight.w600 : FontWeight.w500, color: onChanged == null ? Brand.ink3 : Brand.ink)),
              ),
          },
        ),
      );
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Runs an API call, shows errors, and opens the upgrade screen for 402s.
Future<T?> guard<T>(BuildContext context, Future<T> Function() fn, {void Function()? onUpgrade}) async {
  try {
    return await fn();
  } on ApiException catch (e) {
    if (!context.mounted) return null;
    if (e.needsUpgrade) {
      // A native alert on Apple devices, a Material one elsewhere.
      final apple = const {TargetPlatform.iOS, TargetPlatform.macOS}.contains(Theme.of(context).platform);
      final go = await showAdaptiveDialog<bool>(
        context: context,
        builder: (c) => apple
            ? CupertinoAlertDialog(
                title: const Text('Wedding Pass'),
                content: Text(e.message),
                actions: [
                  CupertinoDialogAction(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
                  CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(c, true), child: const Text('See the Pass')),
                ],
              )
            : AlertDialog(
                title: const Text('Wedding Pass'),
                content: Text(e.message),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('See the Wedding Pass')),
                ],
              ),
      );
      if (go == true) onUpgrade?.call();
    } else {
      toast(context, e.message);
    }
    return null;
  }
}

Future<void> openUrl(String url, {bool inApp = false}) async {
  await launchUrl(Uri.parse(url), mode: inApp ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication);
}

Future<void> copy(BuildContext context, String text, String done) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, done);
}

/// Wide (web panel / tablet) vs phone layout.
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

/// Makes AppState available to every screen and rebuilds them when it changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

/// Event times are Sri Lanka time (UTC+5:30, no daylight saving), whatever the device's zone,
/// so a planner abroad and the couple see the same time.
const slOffset = Duration(hours: 5, minutes: 30);
String slToIso(DateTime date, TimeOfDay time) =>
    DateTime.utc(date.year, date.month, date.day, time.hour, time.minute).subtract(slOffset).toIso8601String();
DateTime isoToSl(String iso) => DateTime.parse(iso).toUtc().add(slOffset);

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String fmtSl(String iso) {
  final d = isoToSl(iso);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.day} ${_months[d.month - 1]} ${d.year}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'am' : 'pm'}';
}

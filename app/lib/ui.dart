import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'state.dart';
import 'strings.dart';

/// One design system for the app and the web panel: warm paper, deep ink and a single
/// vermilion accent (the colour of a sindoor mark), an editorial serif for names and numbers,
/// and hairline borders instead of shadows.
class Brand {
  static const paper = Color(0xFFF4EFE7);
  static const surface = Color(0xFFFCFAF6);
  static const sunk = Color(0xFFEBE4D8);
  static const line = Color(0xFFE0D7C8);
  static const ink = Color(0xFF1B1915);
  static const ink2 = Color(0xFF6F665A);
  static const accent = Color(0xFFB0391F);
  static const accentSoft = Color(0xFFF3DED6);
  static const gold = Color(0xFFA98244);
  static const success = Color(0xFF2F6B4A);
  static const warn = Color(0xFF9A5B12);
  // Kept for older screens.
  static const cream = paper;

  static const serif = 'Instrument Serif';
  static const sans = 'Manrope';

  /// Large display type: names, counts, page titles.
  static TextStyle display(double size, {Color color = ink, FontStyle? style}) =>
      TextStyle(fontFamily: serif, fontSize: size, height: 1.02, letterSpacing: -0.5, color: color, fontStyle: style, fontWeight: FontWeight.w400);

  static ThemeData theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: b).copyWith(
      primary: ink,
      onPrimary: surface,
      primaryContainer: accentSoft,
      onPrimaryContainer: ink,
      secondary: accent,
      onSecondary: Colors.white,
      secondaryContainer: sunk,
      onSecondaryContainer: ink,
      tertiary: gold,
      tertiaryContainer: const Color(0xFFF1E6D0),
      onTertiaryContainer: ink,
      error: accent,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: ink2,
      surfaceContainerLowest: surface,
      surfaceContainerLow: surface,
      surfaceContainer: paper,
      surfaceContainerHigh: sunk,
      surfaceContainerHighest: sunk,
      outline: ink2,
      outlineVariant: line,
    );
    final base = Typography.material2021().black.apply(fontFamily: sans, bodyColor: ink, displayColor: ink);
    // Readable for elders: 16px+ body text, large tap targets.
    final text = base.copyWith(
      displayLarge: display(56),
      displayMedium: display(46),
      displaySmall: display(38),
      headlineLarge: display(34),
      headlineMedium: display(30),
      headlineSmall: display(26),
      titleLarge: const TextStyle(fontFamily: sans, fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.25, color: ink),
      titleMedium: const TextStyle(fontFamily: sans, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.1, height: 1.3, color: ink),
      titleSmall: const TextStyle(fontFamily: sans, fontSize: 14, fontWeight: FontWeight.w700, color: ink),
      bodyLarge: const TextStyle(fontFamily: sans, fontSize: 17, height: 1.45, color: ink),
      bodyMedium: const TextStyle(fontFamily: sans, fontSize: 16, height: 1.45, color: ink),
      bodySmall: const TextStyle(fontFamily: sans, fontSize: 13.5, height: 1.4, color: ink2),
      labelLarge: const TextStyle(fontFamily: sans, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0),
      labelMedium: const TextStyle(fontFamily: sans, fontSize: 13, fontWeight: FontWeight.w600, color: ink2),
    );
    const pill = StadiumBorder();
    final r14 = BorderRadius.circular(14);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: sans,
      textTheme: text,
      scaffoldBackgroundColor: paper,
      canvasColor: paper,
      dividerColor: line,
      splashFactory: InkSparkle.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        toolbarHeight: 62,
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        foregroundColor: ink,
        // Secondary screens get an editorial serif title; the main shell draws its own header.
        titleTextStyle: TextStyle(fontFamily: serif, fontSize: 28, color: ink, letterSpacing: -0.4, height: 1.1),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: surface,
          disabledBackgroundColor: line,
          minimumSize: const Size(64, 54),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: pill,
          textStyle: const TextStyle(fontFamily: sans, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          side: const BorderSide(color: line, width: 1.2),
          backgroundColor: surface,
          shape: pill,
          textStyle: const TextStyle(fontFamily: sans, fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(48, 44),
          shape: pill,
          textStyle: const TextStyle(fontFamily: sans, fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: ink)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        labelStyle: const TextStyle(color: ink2, fontWeight: FontWeight.w500),
        floatingLabelStyle: const TextStyle(color: ink, fontWeight: FontWeight.w700),
        hintStyle: TextStyle(color: ink2.withValues(alpha: 0.7)),
        prefixIconColor: ink2,
        border: OutlineInputBorder(borderRadius: r14, borderSide: const BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: r14, borderSide: const BorderSide(color: line)),
        disabledBorder: OutlineInputBorder(borderRadius: r14, borderSide: BorderSide(color: line.withValues(alpha: 0.6))),
        focusedBorder: OutlineInputBorder(borderRadius: r14, borderSide: const BorderSide(color: ink, width: 1.6)),
        errorBorder: OutlineInputBorder(borderRadius: r14, borderSide: const BorderSide(color: accent)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: line)),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: ink,
        titleTextStyle: TextStyle(fontFamily: sans, fontSize: 16, fontWeight: FontWeight.w600, color: ink, height: 1.3),
        subtitleTextStyle: TextStyle(fontFamily: sans, fontSize: 14, color: ink2, height: 1.35),
        contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: ink,
        disabledColor: sunk,
        checkmarkColor: surface,
        showCheckmark: false,
        side: const BorderSide(color: line),
        shape: pill,
        // Unselected chips use labelStyle, selected ones secondaryLabelStyle.
        labelStyle: const TextStyle(fontFamily: sans, fontSize: 14, fontWeight: FontWeight.w700, color: ink),
        secondaryLabelStyle: const TextStyle(fontFamily: sans, fontSize: 14, fontWeight: FontWeight.w700, color: surface),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? ink : surface),
          foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? surface : ink),
          side: const WidgetStatePropertyAll(BorderSide(color: line)),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: sans, fontWeight: FontWeight.w700)),
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? ink : sunk),
        thumbColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? surface : ink2),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? ink : Colors.transparent),
        side: const BorderSide(color: ink2, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? ink : ink2)),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent, linearTrackColor: sunk, circularTrackColor: sunk),
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: line,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        titleTextStyle: display(28),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shadowColor: ink.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: line)),
        textStyle: const TextStyle(fontFamily: sans, fontSize: 15, fontWeight: FontWeight.w600, color: ink),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: const TextStyle(fontFamily: sans, color: surface, fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: ink,
        unselectedLabelColor: ink2,
        indicatorColor: accent,
        dividerColor: line,
        labelStyle: TextStyle(fontFamily: sans, fontWeight: FontWeight.w700, fontSize: 15),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: paper,
        indicatorColor: ink,
        selectedIconTheme: IconThemeData(color: surface),
        unselectedIconTheme: IconThemeData(color: ink2),
        selectedLabelTextStyle: TextStyle(fontFamily: sans, fontWeight: FontWeight.w700, color: ink),
        unselectedLabelTextStyle: TextStyle(fontFamily: sans, fontWeight: FontWeight.w600, color: ink2),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: paper,
        indicatorColor: ink,
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(color: st.contains(WidgetState.selected) ? surface : ink2)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: ink, foregroundColor: surface, shape: StadiumBorder(), elevation: 0),
      expansionTileTheme: const ExpansionTileThemeData(shape: Border(), collapsedShape: Border()),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        headerHeadlineStyle: display(34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      timePickerTheme: TimePickerThemeData(backgroundColor: paper, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
    );
  }
}

/// Short-hand for translated text from the current locale.
extension Tr on AppState {
  String t(String key, [Map<String, Object>? vars]) => tr(locale, key, vars);
}

/// Content column that stays readable on wide web-panel screens.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 720, this.padding = const EdgeInsets.all(16)});
  final List<Widget> children;
  final double maxWidth;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => ListView(
        // Leaves room for the floating dock, which the page scrolls behind.
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(padding: padding, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
            ),
          ),
        ],
      );
}

/// Every empty screen says what to do next, with one button.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.body, required this.action, required this.onAction});
  final IconData icon;
  final String title, body, action;
  final VoidCallback onAction;
  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(color: Brand.accentSoft, shape: BoxShape.circle, border: Border.all(color: Brand.line)),
                child: Icon(icon, size: 36, color: Brand.accent),
              ),
              const SizedBox(height: 24),
              Text(title, style: Brand.display(32), textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Brand.ink2)),
              const SizedBox(height: 28),
              FilledButton(onPressed: onAction, child: Text(action)),
            ]),
          ),
        ),
      );
}

/// Stat cells in rows of [cols], drawn as one ruled panel rather than separate cards. Each row
/// is as tall as its tallest cell, so the label never clips on a narrow phone or with a larger
/// text size.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.cols, required this.children});
  final int cols;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += cols) {
      if (i > 0) rows.add(const Divider());
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var j = i; j < i + cols; j++) ...[
            if (j > i) const VerticalDivider(width: 1, thickness: 1, color: Brand.line),
            Expanded(child: j < children.length ? children[j] : const SizedBox()),
          ],
        ]),
      ));
    }
    return Panel(padding: EdgeInsets.zero, child: Column(children: rows));
  }
}

class StatTile extends StatelessWidget {
  const StatTile(this.label, this.value, {super.key, this.color});
  final String label;
  final Object value;
  final Color? color;
  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('$value', maxLines: 1, style: Brand.display(40, color: color ?? Brand.ink))),
            const SizedBox(height: 6),
            Eyebrow(label),
          ]),
        ),
      );
}

/// Small tracked uppercase label above a title or under a number.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(fontFamily: Brand.sans, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: color ?? Brand.ink2, height: 1.2),
      );
}

/// Section heading: an optional eyebrow (or step number), a serif title and an optional action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.eyebrow, this.trailing, this.size = 28, this.padding = const EdgeInsets.fromLTRB(2, 28, 2, 12)});
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
              if (eyebrow != null) ...[Eyebrow(eyebrow!, color: Brand.accent), const SizedBox(height: 6)],
              Semantics(header: true, child: Text(title, style: Brand.display(size))),
            ]),
          ),
          ?trailing,
        ]),
      );
}

/// The basic surface: a paper-white panel with a hairline border. Tappable when [onTap] is set.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.onTap, this.color, this.borderColor, this.radius = 22, this.margin = const EdgeInsets.symmetric(vertical: 6)});
  final Widget child;
  final EdgeInsets padding, margin;
  final VoidCallback? onTap;
  final Color? color, borderColor;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: borderColor ?? Brand.line));
    return Padding(
      padding: margin,
      child: Material(
        color: color ?? Brand.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

/// A row in a list panel: a tinted icon tile, a title and a line of detail, then a chevron
/// (or whatever [trailing] gives).
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
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            IconTile(icon, tint: tint),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.25)),
                if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: const TextStyle(fontSize: 14, color: Brand.ink2, height: 1.35))],
              ]),
            ),
            const SizedBox(width: 8),
            trailing ?? const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: Brand.ink2),
          ]),
        ),
      );
}

/// Several rows in one panel, ruled between them.
class RowGroup extends StatelessWidget {
  const RowGroup({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Panel(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(indent: 16, endIndent: 16), children[i]],
        ]),
      );
}

class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.tint, this.size = 44});
  final IconData icon;
  final Color? tint;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = tint ?? Brand.ink;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tint == null ? Brand.sunk : c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(icon, size: size * 0.48, color: c),
    );
  }
}

/// Initials in a circle, coloured from the name so the same guest always looks the same.
class Monogram extends StatelessWidget {
  const Monogram(this.name, {super.key, this.size = 42});
  final String name;
  final double size;
  static const _tints = [Color(0xFFE9D9C4), Color(0xFFDCE3D3), Color(0xFFF0D8CF), Color(0xFFDAD9E6), Color(0xFFE6DCC9), Color(0xFFD7E2E0)];
  @override
  Widget build(BuildContext context) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = words.isEmpty ? '?' : (words.length == 1 ? words.first.characters.first : '${words.first.characters.first}${words.last.characters.first}').toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: _tints[name.hashCode.abs() % _tints.length], shape: BoxShape.circle),
        child: Text(initials, style: TextStyle(fontFamily: Brand.serif, fontSize: size * 0.44, color: Brand.ink, height: 1)),
      ),
    );
  }
}

/// A short status label with a coloured dot.
class StatusTag extends StatelessWidget {
  const StatusTag(this.label, this.color, {super.key, this.filled = false});
  final String label;
  final Color color;
  final bool filled;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: filled ? 0.14 : 0.08), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
        ]),
      );
}

/// A short ornament between sections: a hairline with a small diamond in the middle.
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

/// Couple names set as a pair, the ampersand in italic accent.
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
          style: Brand.display(size, color: color),
        ),
      );
}

/// Phone navigation: a floating ink dock; the open tab shows its name.
class DockNav extends StatelessWidget {
  const DockNav({super.key, required this.items, required this.index, required this.onTap});
  final List<(String, IconData)> items;
  final int index;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 6, 14, bottom > 0 ? bottom : 14),
      child: Container(
        height: 66,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(color: Brand.ink, borderRadius: BorderRadius.circular(99)),
        child: Row(children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              flex: i == index ? 2 : 1,
              child: Semantics(
                button: true,
                selected: i == index,
                label: items[i].$1,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTap(i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(color: i == index ? Brand.paper : Colors.transparent, borderRadius: BorderRadius.circular(99)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(items[i].$2, size: 22, color: i == index ? Brand.ink : Brand.paper.withValues(alpha: 0.62)),
                      if (i == index) ...[
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(items[i].$1, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Brand.ink)),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// A thin bar split into coloured parts (e.g. coming / maybe / not coming / no reply).
class SplitBar extends StatelessWidget {
  const SplitBar({super.key, required this.parts, this.height = 10});
  final List<(num, Color)> parts;
  final double height;
  @override
  Widget build(BuildContext context) {
    final total = parts.fold<num>(0, (a, p) => a + p.$1);
    return ClipRRect(
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
  }
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
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      decoration: BoxDecoration(color: Brand.ink, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        const Icon(Icons.cloud_off_rounded, color: Brand.paper, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Semantics(liveRegion: true, child: Text(s.t('offlineCopy', {'time': time}), style: const TextStyle(color: Brand.paper, fontSize: 14, fontWeight: FontWeight.w600)))),
        TextButton(onPressed: onRetry, style: TextButton.styleFrom(foregroundColor: Brand.paper), child: Text(s.t('retry'))),
      ]),
    );
  }
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
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
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

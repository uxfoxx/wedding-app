import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'state.dart';
import 'strings.dart';

/// One design system for the app and the web panel.
class Brand {
  static const gold = Color(0xFFA8742A);
  static const ink = Color(0xFF2B1D12);
  static const cream = Color(0xFFFBF6EC);

  static ThemeData theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: gold, brightness: b);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: b == Brightness.light ? cream : null,
      // Readable for elders: 16px+ body text, large tap targets.
      textTheme: Typography.material2021().black.apply(fontSizeFactor: 1.0).copyWith(
            bodyMedium: const TextStyle(fontSize: 16, height: 1.45),
            bodyLarge: const TextStyle(fontSize: 17, height: 1.45),
          ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(64, 52), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52), textStyle: const TextStyle(fontSize: 16))),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), filled: true),
      cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(vertical: 6)),
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
        padding: EdgeInsets.zero,
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
        child: Column(children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton(onPressed: onAction, child: Text(action)),
        ]),
      );
}

/// Stat tiles in rows of [cols]. Each row is as tall as its tallest tile, so the label never
/// clips on a narrow phone or with a larger text size (a fixed aspect ratio did both).
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.cols, required this.children});
  final int cols;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < children.length; i += cols)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var j = i; j < i + cols; j++) Expanded(child: j < children.length ? children[j] : const SizedBox()),
            ]),
          ),
      ]);
}

class StatTile extends StatelessWidget {
  const StatTile(this.label, this.value, {super.key, this.color});
  final String label;
  final Object value;
  final Color? color;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$value', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: color ?? Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
            Text(label),
          ]),
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

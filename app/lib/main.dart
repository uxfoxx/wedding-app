import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'api.dart';
import 'screens/onboarding.dart';
import 'screens/shell.dart';
import 'screens/sign_in.dart';
import 'state.dart';
import 'ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Browser tests read the accessibility tree; real users get it when a screen reader asks.
  if (const bool.fromEnvironment('E2E')) SemanticsBinding.instance.ensureSemantics();
  // Web panel links carry a session (#session=...) after an email sign-in link,
  // or a co-owner invite (#join=...).
  String? session, join;
  if (kIsWeb && Uri.base.fragment.isNotEmpty) {
    final f = Uri.splitQueryString(Uri.base.fragment.replaceFirst(RegExp(r'^/'), ''));
    session = f['session'];
    join = f['join'];
  }
  final state = AppState(Api())..init(sessionFromUrl: session, joinFromUrl: join);
  runApp(WeddingApp(state: state));
}

class WeddingApp extends StatelessWidget {
  const WeddingApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Wedding',
        debugShowCheckedModeBanner: false,
        theme: Brand.theme(Brightness.light),
        home: const Root(),
      ),
    );
  }
}

/// Signed out → sign-in; no wedding yet → first-run flow; otherwise the main tabs.
class Root extends StatelessWidget {
  const Root({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (!s.ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (s.user == null) return const SignInScreen();
    if (s.summary == null) return const OnboardingScreen();
    return const Shell();
  }
}

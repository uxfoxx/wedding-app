import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui.dart';

/// Email code is the default (free). Phone OTP is offered but costs an SMS per sign-in.
/// Google and Apple buttons are added once the OAuth client IDs exist (see README).
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool phone = false;
  bool codeSent = false;
  bool busy = false;
  final address = TextEditingController();
  final code = TextEditingController();
  String? devHint;

  Future<void> start() async {
    final s = AppScope.read(context);
    setState(() => busy = true);
    final r = await guard(context, () => s.api.post(phone ? '/auth/phone/start' : '/auth/email/start', {phone ? 'phone' : 'email': address.text.trim()}));
    setState(() {
      busy = false;
      if (r != null) {
        codeSent = true;
        devHint = r['devCode'] as String?; // development servers only
      }
    });
  }

  Future<void> verify() async {
    final s = AppScope.read(context);
    setState(() => busy = true);
    final r = await guard(context, () => s.api.post(phone ? '/auth/phone/verify' : '/auth/email/verify', {phone ? 'phone' : 'email': address.text.trim(), 'code': code.text.trim()}));
    if (r != null && mounted) await guard(context, () => s.setSession(r['token'] as String));
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final form = <Widget>[
      if (!codeSent) ...[
        Eyebrow(s.t(phone ? 'phone' : 'email')),
        const SizedBox(height: 10),
        TextField(
          key: const Key('address'),
          controller: address,
          keyboardType: phone ? TextInputType.phone : TextInputType.emailAddress,
          autofillHints: [phone ? AutofillHints.telephoneNumber : AutofillHints.email],
          decoration: InputDecoration(
            hintText: phone ? '07X XXX XXXX' : 'you@example.com',
            prefixIcon: Icon(phone ? Icons.phone_iphone_rounded : Icons.alternate_email_rounded),
          ),
          onSubmitted: (_) => start(),
        ),
        const SizedBox(height: 14),
        FilledButton(key: const Key('sendCode'), onPressed: busy ? null : start, child: Text(s.t('sendCode'))),
        const SizedBox(height: 6),
        TextButton(onPressed: () => setState(() => phone = !phone), child: Text(s.t(phone ? 'continueEmailInstead' : 'continuePhone'))),
      ] else ...[
        Text(s.t('codeSent', {'to': address.text.trim()}), style: const TextStyle(fontWeight: FontWeight.w600)),
        if (devHint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Development code: $devHint', style: const TextStyle(color: Brand.ink2))),
        const SizedBox(height: 18),
        Eyebrow(s.t('code')),
        const SizedBox(height: 10),
        TextField(
          key: const Key('code'),
          controller: code,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, letterSpacing: 12, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(hintText: '••••••', counterText: ''),
          onSubmitted: (_) => verify(),
        ),
        const SizedBox(height: 14),
        FilledButton(key: const Key('verify'), onPressed: busy ? null : verify, child: Text(s.t('verify'))),
        const SizedBox(height: 6),
        TextButton(onPressed: () => setState(() => codeSent = false), child: Text(s.t('back'))),
      ],
    ];
    // Cover: the promise, set like an invitation.
    final cover = Container(
      color: Brand.ink,
      child: Stack(children: [
        const Positioned(top: 60, right: -170, child: _Rings(size: 320)),
        SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(s.t('appName'), style: Brand.display(26, color: Brand.paper, style: FontStyle.italic)),
                    const Spacer(),
                    _LangPicker(),
                  ]),
                  const SizedBox(height: 56),
                  const Flourish(color: Color(0xFFE9B97A), width: 80),
                  const SizedBox(height: 22),
                  Text(s.t('welcome'), style: Brand.display(46, color: Brand.paper).copyWith(height: 1.05)),
                  const SizedBox(height: 14),
                  Text(s.t('welcomeSub'), style: TextStyle(color: Brand.paper.withValues(alpha: 0.68), fontSize: 16.5, height: 1.45)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
    // Sheet: the form, its rounded top cut into the cover (ink behind the corners).
    final sheet = ColoredBox(
      color: Brand.ink,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(color: Brand.paper, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: form),
              ),
            ),
          ),
        ),
      ),
    );
    // Paper behind everything, so the sheet reaches the bottom however short the form is.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(body: SingleChildScrollView(child: Column(children: [cover, sheet]))),
    );
  }
}

/// Thin concentric rings, like the edge of a wax seal.
class _Rings extends StatelessWidget {
  const _Rings({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(child: CustomPaint(size: Size.square(size), painter: _RingsPainter()));
}

class _RingsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 6; i++) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFE9B97A).withValues(alpha: 0.10 + i * 0.03);
      canvas.drawCircle(c, size.width / 2 - i * 22, p);
    }
    canvas.drawCircle(c, 5, Paint()..color = Brand.accent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LangPicker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: Brand.paper.withValues(alpha: 0.2))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final l in const [('en', 'EN', 'English'), ('si', 'සිං', 'සිංහල'), ('ta', 'த', 'தமிழ்')])
          Semantics(
            button: true,
            selected: s.locale == l.$1,
            label: l.$3,
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => s.setLocale(l.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: s.locale == l.$1 ? Brand.paper : Colors.transparent, borderRadius: BorderRadius.circular(99)),
                child: Text(l.$2, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: s.locale == l.$1 ? Brand.ink : Brand.paper)),
              ),
            ),
          ),
      ]),
    );
  }
}

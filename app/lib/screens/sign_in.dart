import 'package:flutter/cupertino.dart';
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
        TextField(
          key: const Key('address'),
          controller: address,
          keyboardType: phone ? TextInputType.phone : TextInputType.emailAddress,
          autofillHints: [phone ? AutofillHints.telephoneNumber : AutofillHints.email],
          decoration: InputDecoration(
            labelText: s.t(phone ? 'phone' : 'email'),
            hintText: phone ? '07X XXX XXXX' : 'you@example.com',
            prefixIcon: Icon(phone ? CupertinoIcons.phone : CupertinoIcons.mail),
          ),
          onSubmitted: (_) => start(),
        ),
        const SizedBox(height: 12),
        FilledButton(key: const Key('sendCode'), onPressed: busy ? null : start, child: busy ? const CupertinoActivityIndicator(color: Colors.white) : Text(s.t('sendCode'))),
        const SizedBox(height: 4),
        TextButton(onPressed: () => setState(() => phone = !phone), child: Text(s.t(phone ? 'continueEmailInstead' : 'continuePhone'))),
      ] else ...[
        Text(s.t('codeSent', {'to': address.text.trim()}), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        if (devHint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Development code: $devHint', textAlign: TextAlign.center, style: const TextStyle(color: Brand.ink2, fontSize: 14))),
        const SizedBox(height: 14),
        TextField(
          key: const Key('code'),
          controller: code,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: Brand.sansDisplay, fontSize: 30, letterSpacing: 14, fontWeight: FontWeight.w600),
          decoration: InputDecoration(hintText: '••••••', counterText: '', semanticCounterText: '', labelText: null, helperText: null, hintStyle: TextStyle(color: Brand.ink3.withValues(alpha: 0.7), letterSpacing: 14)),
          onSubmitted: (_) => verify(),
        ),
        const SizedBox(height: 12),
        FilledButton(key: const Key('verify'), onPressed: busy ? null : verify, child: busy ? const CupertinoActivityIndicator(color: Colors.white) : Text(s.t('verify'))),
        TextButton(onPressed: () => setState(() => codeSent = false), child: Text(s.t('back'))),
      ],
    ];
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1020),
        body: Stack(children: [
          const Positioned.fill(child: MeshBackdrop()),
          LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, top + 10, 20, MediaQuery.paddingOf(context).bottom + 16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          const Icon(CupertinoIcons.heart_fill, color: Colors.white, size: 22),
                          const SizedBox(width: 8),
                          Text(s.t('appName'), style: Brand.display(20, color: Colors.white)),
                          const Spacer(),
                          _LangPicker(),
                        ]),
                        SizedBox(height: box.maxHeight * 0.16),
                        Reveal(index: 0, offset: 0.2, child: Text(s.t('welcome'), style: Brand.display(42, color: Colors.white).copyWith(height: 1.04))),
                        const SizedBox(height: 14),
                        Reveal(index: 1, child: Text(s.t('welcomeSub'), style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 17, height: 1.4))),
                        SizedBox(height: box.maxHeight * 0.08),
                        Reveal(
                          index: 2,
                          offset: 0.15,
                          child: Glass(
                            radius: 30,
                            opacity: 0.8,
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                            child: AnimatedSize(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: form),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _LangPicker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Glass(
      dark: true,
      radius: 99,
      opacity: 0.25,
      padding: const EdgeInsets.all(3),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final l in const [('en', 'EN', 'English'), ('si', 'සිං', 'සිංහල'), ('ta', 'த', 'தமிழ்')])
          Semantics(
            button: true,
            selected: s.locale == l.$1,
            label: l.$3,
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                s.setLocale(l.$1);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 34),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: s.locale == l.$1 ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(99)),
                child: Text(l.$2, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: s.locale == l.$1 ? Brand.ink : Colors.white)),
              ),
            ),
          ),
      ]),
    );
  }
}

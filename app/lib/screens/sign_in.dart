import 'package:flutter/material.dart';

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
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: PageBody(maxWidth: 460, padding: const EdgeInsets.fromLTRB(20, 32, 20, 32), children: [
          Align(alignment: Alignment.centerRight, child: _LangPicker()),
          const SizedBox(height: 24),
          Icon(Icons.favorite, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(s.t('welcome'), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(s.t('welcomeSub'), style: theme.textTheme.bodyLarge),
          const SizedBox(height: 32),
          if (!codeSent) ...[
            TextField(
              key: const Key('address'),
              controller: address,
              keyboardType: phone ? TextInputType.phone : TextInputType.emailAddress,
              autofillHints: [phone ? AutofillHints.telephoneNumber : AutofillHints.email],
              decoration: InputDecoration(labelText: s.t(phone ? 'phone' : 'email'), hintText: phone ? '07X XXX XXXX' : null),
              onSubmitted: (_) => start(),
            ),
            const SizedBox(height: 16),
            FilledButton(key: const Key('sendCode'), onPressed: busy ? null : start, child: Text(s.t('sendCode'))),
            const SizedBox(height: 8),
            TextButton(onPressed: () => setState(() => phone = !phone), child: Text(s.t(phone ? 'continueEmailInstead' : 'continuePhone'))),
          ] else ...[
            Text(s.t('codeSent', {'to': address.text.trim()})),
            if (devHint != null) Text('Development code: $devHint', style: TextStyle(color: theme.colorScheme.outline)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('code'),
              controller: code,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 6,
              decoration: InputDecoration(labelText: s.t('code')),
              onSubmitted: (_) => verify(),
            ),
            FilledButton(key: const Key('verify'), onPressed: busy ? null : verify, child: Text(s.t('verify'))),
            TextButton(onPressed: () => setState(() => codeSent = false), child: Text(s.t('back'))),
          ],
        ]),
      ),
    );
  }
}

class _LangPicker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: const [ButtonSegment(value: 'en', label: Text('EN')), ButtonSegment(value: 'si', label: Text('සිං')), ButtonSegment(value: 'ta', label: Text('த'))],
      selected: {s.locale},
      onSelectionChanged: (v) => s.setLocale(v.first),
    );
  }
}

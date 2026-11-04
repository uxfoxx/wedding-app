import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ui.dart';
import 'onboarding.dart';
import 'vendor_setup.dart';

/// One app, one sign-in; the account type decides what you see.
class RoleChoiceScreen extends StatelessWidget {
  const RoleChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    Widget option(String n, IconData icon, String title, String sub, Key key, VoidCallback onTap) => Panel(
          key: key,
          onTap: onTap,
          padding: const EdgeInsets.all(20),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  IconTile(icon, tint: Brand.accent, size: 40),
                  const Spacer(),
                  Text(n, style: Brand.display(17, color: Brand.ink3)),
                ]),
                const SizedBox(height: 18),
                Text(title, style: Brand.display(22)),
                const SizedBox(height: 6),
                Text(sub, style: const TextStyle(color: Brand.ink2, fontSize: 15)),
              ]),
            ),
          ]),
        );
    return Scaffold(
      appBar: AppBar(actions: [TextButton(onPressed: () => s.signOut(), child: Text(s.t('signOut'))), const SizedBox(width: 8)]),
      body: SafeArea(bottom: false,
        child: PageBody(maxWidth: 560, padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
          const SectionHeader('Welcome!', size: 40, padding: EdgeInsets.fromLTRB(4, 0, 4, 8)),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 18),
            child: Text('Tell us how you will use the app. You can add another role later.', style: TextStyle(color: Brand.ink2, fontSize: 16.5)),
          ),
          option('01', CupertinoIcons.heart_fill, "I'm planning my wedding", 'For the couple or a family member organising it.', const Key('roleCouple'),
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingScreen(canCancel: true)))),
          option('02', CupertinoIcons.briefcase_fill, "I'm a wedding planner", 'Run all your client weddings, team and tasks in one place.', const Key('rolePlanner'),
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlannerSetupScreen()))),
          option('03', CupertinoIcons.camera_fill, 'I offer wedding services', 'Photographers, decorators, venues and more: get enquiries from couples.', const Key('roleVendor'),
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VendorSetupScreen()))),
        ]),
      ),
    );
  }
}

class PlannerSetupScreen extends StatefulWidget {
  const PlannerSetupScreen({super.key});
  @override
  State<PlannerSetupScreen> createState() => _PlannerSetupScreenState();
}

class _PlannerSetupScreenState extends State<PlannerSetupScreen> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final district = TextEditingController();
  bool busy = false;

  Future<void> save() async {
    final s = AppScope.read(context);
    if (name.text.trim().isEmpty) {
      toast(context, 'Add your business name.');
      return;
    }
    setState(() => busy = true);
    final r = await guard(context, () => s.api.post('/planners', {'business_name': name.text.trim(), 'phone': phone.text.trim(), 'district': district.text.trim()}));
    if (r != null) {
      await s.becamePlanner();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Your planner business')),
        body: SafeArea(bottom: false,
          child: PageBody(maxWidth: 560, children: [
            const Text('We check every planner business. You can start your first client wedding straight away.'),
            const SizedBox(height: 16),
            TextField(key: const Key('bizName'), controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Business name')),
            const SizedBox(height: 12),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Business phone / WhatsApp')),
            const SizedBox(height: 12),
            TextField(controller: district, decoration: const InputDecoration(labelText: 'District')),
            const SizedBox(height: 20),
            FilledButton(key: const Key('bizSave'), onPressed: busy ? null : save, child: const Text('Create my planner account')),
          ]),
        ),
      );
}

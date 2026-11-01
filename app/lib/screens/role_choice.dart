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
    final th = Theme.of(context);
    Widget option(IconData icon, String title, String sub, Key key, VoidCallback onTap) => Card(
          child: ListTile(
            key: key,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            leading: Icon(icon, size: 34, color: th.colorScheme.primary),
            title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            subtitle: Text(sub),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        );
    return Scaffold(
      appBar: AppBar(actions: [TextButton(onPressed: () => s.signOut(), child: Text(s.t('signOut')))]),
      body: SafeArea(
        child: PageBody(maxWidth: 560, children: [
          Text('Welcome!', style: th.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Tell us how you will use the app. You can add another role later.'),
          const SizedBox(height: 20),
          option(Icons.favorite_outline, "I'm planning my wedding", 'For the couple or a family member organising it.', const Key('roleCouple'),
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingScreen(canCancel: true)))),
          option(Icons.business_center_outlined, "I'm a wedding planner", 'Run all your client weddings, team and tasks in one place.', const Key('rolePlanner'),
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlannerSetupScreen()))),
          option(Icons.storefront_outlined, 'I offer wedding services', 'Photographers, decorators, venues and more: get enquiries from couples.', const Key('roleVendor'),
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
        body: SafeArea(
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

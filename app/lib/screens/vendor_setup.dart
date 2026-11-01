import 'package:flutter/material.dart';

import '../ui.dart';

const sriLankaDistricts = [
  'Colombo', 'Gampaha', 'Kalutara', 'Kandy', 'Matale', 'Nuwara Eliya', 'Galle', 'Matara', 'Hambantota', 'Jaffna', 'Kilinochchi', 'Mannar', 'Vavuniya',
  'Mullaitivu', 'Batticaloa', 'Ampara', 'Trincomalee', 'Kurunegala', 'Puttalam', 'Anuradhapura', 'Polonnaruwa', 'Badulla', 'Monaragala', 'Ratnapura', 'Kegalle',
];

class VendorSetupScreen extends StatefulWidget {
  const VendorSetupScreen({super.key});
  @override
  State<VendorSetupScreen> createState() => _VendorSetupScreenState();
}

class _VendorSetupScreenState extends State<VendorSetupScreen> {
  List<dynamic> categories = [];
  String? category;
  String district = 'Colombo';
  final areas = <String>{'Colombo'};
  final langs = <String>{'si', 'en'};
  final name = TextEditingController();
  final phone = TextEditingController();
  final years = TextEditingController();
  final about = TextEditingController();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final r = await guard(context, () => AppScope.read(context).api.get('/vendor-categories'));
      if (r != null && mounted) setState(() => categories = r['categories'] as List<dynamic>);
    });
  }

  Future<void> save() async {
    final s = AppScope.read(context);
    if (name.text.trim().isEmpty || category == null || phone.text.trim().isEmpty) {
      toast(context, 'Add your business name, category and phone.');
      return;
    }
    setState(() => busy = true);
    final r = await guard(context, () => s.api.post('/vendors', {
          'business_name': name.text.trim(), 'category': category, 'district': district, 'service_areas': areas.toList(), 'languages': langs.toList(),
          'phone': phone.text.trim(), 'whatsapp': phone.text.trim(), 'years_active': int.tryParse(years.text), 'description': about.text.trim(),
        }));
    if (r != null) {
      await s.becameVendor();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Your business')),
      body: SafeArea(
        child: PageBody(maxWidth: 640, children: [
          const Text('Couples contact you directly. Listing is free. Our team checks every business before it goes live.'),
          const SizedBox(height: 16),
          TextField(key: const Key('vName'), controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Business name')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('vCategory'),
            initialValue: category,
            decoration: const InputDecoration(labelText: 'What do you offer?'),
            items: [for (final c in categories) DropdownMenuItem(value: c['id'] as String, child: Text(c['name'] as String))],
            onChanged: (v) => setState(() => category = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: district,
            decoration: const InputDecoration(labelText: 'Based in'),
            items: [for (final d in sriLankaDistricts) DropdownMenuItem(value: d, child: Text(d))],
            onChanged: (v) => setState(() { district = v!; areas.add(v); }),
          ),
          const SizedBox(height: 12),
          Text('Districts you serve', style: th.textTheme.titleSmall),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final d in sriLankaDistricts) FilterChip(label: Text(d), selected: areas.contains(d), onSelected: (v) => setState(() => v ? areas.add(d) : areas.remove(d))),
          ]),
          const SizedBox(height: 12),
          Text('Languages', style: th.textTheme.titleSmall),
          Wrap(spacing: 6, children: [
            for (final l in const [('si', 'සිංහල'), ('ta', 'தமிழ்'), ('en', 'English')]) FilterChip(label: Text(l.$2), selected: langs.contains(l.$1), onSelected: (v) => setState(() => v ? langs.add(l.$1) : langs.remove(l.$1))),
          ]),
          const SizedBox(height: 12),
          TextField(key: const Key('vPhone'), controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone / WhatsApp', helperText: 'We verify this number before you go live')),
          const SizedBox(height: 12),
          TextField(controller: years, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Years in business')),
          const SizedBox(height: 12),
          TextField(controller: about, maxLines: 5, decoration: const InputDecoration(labelText: 'About your business')),
          const SizedBox(height: 20),
          FilledButton(key: const Key('vSave'), onPressed: busy ? null : save, child: const Text('Create my business profile')),
        ]),
      ),
    );
  }
}

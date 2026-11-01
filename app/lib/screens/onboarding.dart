import 'package:flutter/material.dart';

import '../ui.dart';

/// First run: what are you planning → Easy or Advanced → names, ceremony, date, venue.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.canCancel = false});
  final bool canCancel;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int step = 0;
  String kind = 'wedding';
  String mode = 'easy';
  String type = 'buddhist';
  final p1 = TextEditingController();
  final p2 = TextEditingController();
  final venue = TextEditingController();
  final address = TextEditingController();
  DateTime? date;
  TimeOfDay time = const TimeOfDay(hour: 10, minute: 0);
  bool busy = false;

  static const types = {'buddhist': 'Buddhist (Poruwa)', 'hindu': 'Hindu (Kovil)', 'christian': 'Christian (Church)', 'muslim': 'Muslim (Nikah)', 'civil': 'Civil registration', 'mixed': 'Mixed / other'};

  Future<void> create() async {
    final s = AppScope.read(context);
    if (p1.text.trim().isEmpty || p2.text.trim().isEmpty || date == null) {
      toast(context, 'Please add both names and the date.');
      return;
    }
    setState(() => busy = true);
    final r = await guard(context, () => s.api.post('/weddings', {
          'kind': kind, 'mode': mode, 'wedding_type': type, 'language': s.locale,
          'partner1': p1.text.trim(), 'partner2': p2.text.trim(),
          'event': {'starts_at': slToIso(date!, time), 'venue': venue.text.trim(), 'address': address.text.trim()},
        }));
    if (r != null) {
      await s.createdWedding(r);
      if (mounted && widget.canCancel) Navigator.of(context).pop();
    }
    if (mounted) setState(() => busy = false);
  }

  Widget choice(String label, String sub, IconData icon, bool selected, VoidCallback onTap) => Card(
        color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(icon, size: 32),
          title: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          subtitle: sub.isEmpty ? null : Text(sub),
          trailing: selected ? const Icon(Icons.check_circle) : null,
          onTap: onTap,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context).textTheme;
    final steps = <Widget>[
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('whatPlanning'), style: th.headlineSmall),
        const SizedBox(height: 16),
        for (final k in const [('wedding', Icons.favorite), ('engagement', Icons.diamond_outlined), ('homecoming', Icons.home_outlined), ('other', Icons.celebration_outlined)])
          choice(s.t(k.$1), '', k.$2, kind == k.$1, () => setState(() { kind = k.$1; step = 1; })),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('mode'), style: th.headlineSmall),
        const SizedBox(height: 16),
        choice(s.t('startSimple'), s.t('startSimpleSub'), Icons.bolt, mode == 'easy', () => setState(() { mode = 'easy'; step = 2; })),
        choice(s.t('fullTools'), s.t('fullToolsSub'), Icons.tune, mode == 'advanced', () => setState(() { mode = 'advanced'; step = 2; })),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('names'), style: th.headlineSmall),
        const SizedBox(height: 16),
        TextField(key: const Key('p1'), controller: p1, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: s.t('partner1'))),
        const SizedBox(height: 12),
        TextField(key: const Key('p2'), controller: p2, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: s.t('partner2'))),
        const SizedBox(height: 12),
        if (kind == 'wedding')
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: InputDecoration(labelText: s.t('ceremony')),
            items: [for (final e in types.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => type = v!),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('date'),
              icon: const Icon(Icons.event),
              label: Text(date == null ? s.t('date') : '${date!.day}/${date!.month}/${date!.year}'),
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(context: context, firstDate: now.subtract(const Duration(days: 1)), lastDate: DateTime(now.year + 4), initialDate: date ?? now.add(const Duration(days: 120)));
                if (d != null) setState(() => date = d);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.schedule),
              label: Text(time.format(context)),
              onPressed: () async {
                final t = await showTimePicker(context: context, initialTime: time);
                if (t != null) setState(() => time = t);
              },
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(key: const Key('venue'), controller: venue, decoration: InputDecoration(labelText: s.t('venue'))),
        const SizedBox(height: 12),
        TextField(controller: address, decoration: InputDecoration(labelText: s.t('address'))),
        const SizedBox(height: 20),
        FilledButton(key: const Key('create'), onPressed: busy ? null : create, child: Text(s.t('create'))),
      ]),
    ];
    return Scaffold(
      appBar: AppBar(
        leading: step > 0
            ? IconButton(icon: const Icon(Icons.arrow_back), tooltip: s.t('back'), onPressed: () => setState(() => step--))
            : widget.canCancel ? const CloseButton() : null,
        title: LinearProgressIndicator(value: (step + 1) / 3),
        actions: [if (!widget.canCancel && step == 0) TextButton(onPressed: () => s.signOut(), child: Text(s.t('signOut')))],
      ),
      body: SafeArea(child: PageBody(maxWidth: 560, children: [steps[step]])),
    );
  }
}

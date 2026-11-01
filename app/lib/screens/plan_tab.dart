import 'package:flutter/material.dart';

import '../ui.dart';
import 'upgrade.dart';

const eventKinds = {
  'poruwa': 'Poruwa ceremony', 'church': 'Church ceremony', 'nikah': 'Nikah', 'kovil': 'Kovil ceremony',
  'registration': 'Registration', 'reception': 'Reception', 'homecoming': 'Homecoming', 'engagement': 'Engagement', 'other': 'Other',
};

/// Events (Advanced Mode "Plan" tab). Seating, budget, checklist and run sheet arrive in Phase 2.
class PlanTab extends StatelessWidget {
  const PlanTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final events = (s.summary?['events'] as List?) ?? [];
    return PageBody(children: [
      Text(s.t('events'), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      for (final e in events)
        Card(
          child: ListTile(
            title: Text((e['title'] ?? eventKinds[e['kind']]) as String),
            subtitle: Text([fmtSl(e['starts_at'] as String), if (e['venue'] != null) e['venue'], if (e['nekath'] != null) e['nekath']].join('\n')),
            isThreeLine: true,
            trailing: const Icon(Icons.edit_outlined),
            onTap: s.canEditAll ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventEditor(event: e as Map<String, dynamic>))) : null,
          ),
        ),
      const SizedBox(height: 8),
      if (s.canEditAll)
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EventEditor())),
          icon: const Icon(Icons.add),
          label: Text(s.t('addEvent')),
        ),
      const SizedBox(height: 24),
      Card(
        child: ListTile(
          leading: const Icon(Icons.upcoming_outlined),
          title: const Text('Coming soon'),
          subtitle: const Text('Seating plan, budget, checklist and wedding-day run sheet.'),
        ),
      ),
    ]);
  }
}

class EventEditor extends StatefulWidget {
  const EventEditor({super.key, this.event});
  final Map<String, dynamic>? event;
  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  late final e = widget.event ?? {};
  late String kind = e['kind'] as String? ?? 'reception';
  late final title = TextEditingController(text: e['title'] ?? '');
  late final venue = TextEditingController(text: e['venue'] ?? '');
  late final address = TextEditingController(text: e['address'] ?? '');
  late final maps = TextEditingController(text: e['maps_url'] ?? '');
  late final nekath = TextEditingController(text: e['nekath'] ?? '');
  late final dress = TextEditingController(text: e['dress_code'] ?? '');
  late DateTime date = e['starts_at'] != null ? isoToSl(e['starts_at'] as String) : DateTime.now().add(const Duration(days: 90));
  late TimeOfDay time = TimeOfDay(hour: date.hour, minute: date.minute);
  late List<Map<String, String>> programme = [for (final p in (e['programme'] as List?) ?? []) {'time': '${p['time']}', 'item': '${p['item']}'}];
  bool busy = false;

  Future<void> save() async {
    final s = AppScope.read(context);
    final body = {
      'kind': kind, 'title': title.text.trim(), 'starts_at': slToIso(date, time), 'venue': venue.text.trim(), 'address': address.text.trim(),
      'maps_url': maps.text.trim(), 'nekath': nekath.text.trim(), 'dress_code': dress.text.trim(),
      'programme': programme.where((p) => p['time']!.isNotEmpty && p['item']!.isNotEmpty).toList(),
    };
    setState(() => busy = true);
    final r = await guard(context, () => widget.event == null ? s.api.post('/weddings/${s.weddingId}/events', body) : s.api.patch('/weddings/${s.weddingId}/events/${e['id']}', body), onUpgrade: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UpgradeScreen())));
    if (r != null) {
      await s.refresh();
      if (mounted) Navigator.pop(context);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.event == null ? s.t('addEvent') : eventKinds[kind]!),
        actions: [
          if (widget.event != null)
            IconButton(
              tooltip: s.t('delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final r = await guard(context, () => s.api.delete('/weddings/${s.weddingId}/events/${e['id']}'));
                if (r != null) {
                  await s.refresh();
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body: SafeArea(
        child: PageBody(maxWidth: 600, children: [
          DropdownButtonFormField<String>(
            initialValue: kind,
            decoration: InputDecoration(labelText: s.t('ceremony')),
            items: [for (final k in eventKinds.entries) DropdownMenuItem(value: k.key, child: Text(k.value))],
            onChanged: (v) => setState(() => kind = v!),
          ),
          const SizedBox(height: 12),
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Custom name (optional)')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text('${date.day}/${date.month}/${date.year}'),
                onPressed: () async {
                  final d = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(DateTime.now().year + 4), initialDate: date);
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
          TextField(controller: nekath, decoration: InputDecoration(labelText: s.t('nekath'), hintText: 'Poruwa at 10:24 am')),
          const SizedBox(height: 12),
          TextField(controller: venue, decoration: InputDecoration(labelText: s.t('venue'))),
          const SizedBox(height: 12),
          TextField(controller: address, decoration: InputDecoration(labelText: s.t('address'))),
          const SizedBox(height: 12),
          TextField(controller: maps, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Google Maps link (optional)')),
          const SizedBox(height: 12),
          TextField(controller: dress, decoration: InputDecoration(labelText: s.t('dressCode'))),
          const SizedBox(height: 16),
          Text('Programme', style: Theme.of(context).textTheme.titleMedium),
          for (var i = 0; i < programme.length; i++)
            Row(children: [
              SizedBox(width: 90, child: TextFormField(initialValue: programme[i]['time'], decoration: const InputDecoration(hintText: '10:30'), onChanged: (v) => programme[i]['time'] = v)),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(initialValue: programme[i]['item'], decoration: const InputDecoration(hintText: 'Poruwa ceremony'), onChanged: (v) => programme[i]['item'] = v)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => programme.removeAt(i))),
            ]),
          TextButton.icon(onPressed: () => setState(() => programme.add({'time': '', 'item': ''})), icon: const Icon(Icons.add), label: const Text('Add programme item')),
          const SizedBox(height: 20),
          FilledButton(onPressed: busy ? null : save, child: Text(s.t('save'))),
        ]),
      ),
    );
  }
}

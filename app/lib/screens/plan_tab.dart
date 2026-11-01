import 'package:flutter/material.dart';

import '../ui.dart';
import 'budget.dart';
import 'experience.dart';
import 'marketplace.dart';
import 'planner_tools.dart';
import 'seating.dart';
import 'upgrade.dart';

const eventKinds = {
  'poruwa': 'Poruwa ceremony', 'church': 'Church ceremony', 'nikah': 'Nikah', 'kovil': 'Kovil ceremony',
  'registration': 'Registration', 'reception': 'Reception', 'homecoming': 'Homecoming', 'engagement': 'Engagement', 'other': 'Other',
};

/// Plan hub (Advanced Mode): events, seating, guest experience and planning tools.
class PlanTab extends StatelessWidget {
  const PlanTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    void open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    Widget tile(IconData icon, String title, String sub, Widget screen, {bool paid = false}) => Card(
          child: ListTile(
            leading: Icon(icon, color: th.colorScheme.primary),
            title: Text(title),
            subtitle: Text(sub),
            trailing: paid && !s.isPaid ? const Icon(Icons.lock_outline) : const Icon(Icons.chevron_right),
            onTap: () => paid && !s.isPaid ? open(const UpgradeScreen()) : open(screen),
          ),
        );
    return PageBody(maxWidth: 900, children: [
      const ReadinessCard(),
      const SizedBox(height: 8),
      Text('The day', style: th.textTheme.titleMedium),
      tile(Icons.event_outlined, s.t('events'), 'Ceremonies, times, venues, programme', const EventsScreen()),
      tile(Icons.table_restaurant_outlined, 'Seating', 'Tables, suggested plan, Find your seat', const SeatingScreen(), paid: true),
      tile(Icons.celebration_outlined, 'Guest experience', 'Live updates, menu, photos, guestbook, songs', const ExperienceScreen()),
      tile(Icons.schedule_outlined, 'Run sheet', 'Wedding-day timeline and who does what', const RunSheetScreen(), paid: true),
      tile(Icons.storefront_outlined, 'Vendors', 'Photographers, venues, decorators: suggested for your date and budget', const VendorsScreen()),
      const SizedBox(height: 8),
      Text('Planning', style: th.textTheme.titleMedium),
      tile(Icons.checklist, 'Checklist', 'Suggested tasks by months before the wedding', const TasksScreen(kind: 'checklist'), paid: true),
      tile(Icons.task_alt, 'Tasks', 'To-dos with due dates and owners', const TasksScreen(kind: 'task')),
      tile(Icons.payments_outlined, 'Budget', 'Estimates, payments and what is due', const BudgetScreen(), paid: true),
      tile(Icons.print_outlined, 'Reports', 'Guest list, seating, run sheet, QR board: print or save as PDF', const ReportsScreen()),
      if (s.isPlanner && s.wedding['planner_id'] != null) tile(Icons.sticky_note_2_outlined, 'Client notes and team', 'Private to your planner team', const ClientNotesScreen()),
    ]);
  }
}

/// Events list (was the whole Plan tab in Phase 1).
class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final events = (s.summary?['events'] as List?) ?? [];
    return Scaffold(
      appBar: AppBar(title: Text(s.t('events'))),
      body: PageBody(children: [
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
      ]),
    );
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

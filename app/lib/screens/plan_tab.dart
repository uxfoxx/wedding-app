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
    void open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    Widget tile(IconData icon, String title, String sub, Widget screen, {bool paid = false, Color? tint}) => _PlanTile(
          icon: icon,
          title: title,
          subtitle: sub,
          tint: tint,
          locked: paid && !s.isPaid,
          onTap: () => paid && !s.isPaid ? open(const UpgradeScreen()) : open(screen),
        );
    final day = [
      tile(Icons.event_rounded, s.t('events'), 'Ceremonies, times, venues', const EventsScreen(), tint: Brand.accent),
      tile(Icons.table_restaurant_outlined, 'Seating', 'Tables and Find your seat', const SeatingScreen(), paid: true),
      tile(Icons.celebration_outlined, 'Guest experience', 'Updates, menu, photos, songs', const ExperienceScreen(), tint: Brand.gold),
      tile(Icons.schedule_rounded, 'Run sheet', 'The day, minute by minute', const RunSheetScreen(), paid: true),
      tile(Icons.storefront_outlined, 'Vendors', 'Suggested for your date', const VendorsScreen(), tint: Brand.success),
      tile(Icons.print_outlined, 'Reports', 'Print or save as PDF', const ReportsScreen()),
    ];
    final planning = [
      tile(Icons.checklist_rounded, 'Checklist', 'By months before the day', const TasksScreen(kind: 'checklist'), paid: true),
      tile(Icons.task_alt_rounded, 'Tasks', 'Due dates and owners', const TasksScreen(kind: 'task')),
      tile(Icons.account_balance_wallet_outlined, 'Budget', 'Costs, payments, what is due', const BudgetScreen(), paid: true, tint: Brand.accent),
      if (s.isPlanner && s.wedding['planner_id'] != null) tile(Icons.sticky_note_2_outlined, 'Client notes', 'Private to your team', const ClientNotesScreen()),
    ];
    final cols = isWide(context) ? 3 : 2;
    Widget grid(List<Widget> tiles) => Column(children: [
          for (var i = 0; i < tiles.length; i += cols)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
                  for (var j = i; j < i + cols; j++) Expanded(child: j < tiles.length ? tiles[j] : const SizedBox()),
                ]),
              ),
            ),
        ]);
    return PageBody(maxWidth: 900, padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
      const ReadinessCard(),
      SectionHeader(s.t('theDay'), eyebrow: '01'),
      grid(day),
      SectionHeader(s.t('planning'), eyebrow: '02', padding: const EdgeInsets.fromLTRB(2, 18, 2, 12)),
      grid(planning),
    ]);
  }
}

/// A square-ish tile in the Plan grid: icon, name, one line of detail, a lock when it needs the pass.
class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.icon, required this.title, required this.subtitle, required this.onTap, this.tint, this.locked = false});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final Color? tint;
  final bool locked;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$title. $subtitle${locked ? '. Wedding Pass' : ''}',
        excludeSemantics: true,
        child: Panel(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(16),
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconTile(icon, tint: tint, size: 42),
              const Spacer(),
              if (locked)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: Brand.accentSoft, shape: BoxShape.circle),
                  child: const Icon(Icons.lock_rounded, size: 13, color: Brand.accent),
                ),
            ]),
            const SizedBox(height: 22),
            Text(title, style: Brand.display(24)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 13.5, color: Brand.ink2, height: 1.35)),
          ]),
        ),
      );
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
      body: PageBody(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        for (final e in events) _EventCard(e: e as Map<String, dynamic>, onTap: s.canEditAll ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventEditor(event: e))) : null),
        const SizedBox(height: 12),
        if (s.canEditAll)
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EventEditor())),
            icon: const Icon(Icons.add_rounded),
            label: Text(s.t('addEvent')),
          ),
      ]),
    );
  }
}

/// An event as a date block (day and month) beside its name, time and place.
class _EventCard extends StatelessWidget {
  const _EventCard({required this.e, this.onTap});
  final Map<String, dynamic> e;
  final VoidCallback? onTap;
  static const _mon = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  @override
  Widget build(BuildContext context) {
    final d = isoToSl(e['starts_at'] as String);
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 66,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: Brand.ink, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Text('${d.day}', style: Brand.display(32, color: Brand.paper)),
            const SizedBox(height: 2),
            Text(_mon[d.month - 1], style: const TextStyle(color: Color(0xFFE9B97A), fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((e['title'] ?? eventKinds[e['kind']]) as String, style: Brand.display(25)),
            const SizedBox(height: 4),
            Text(fmtSl(e['starts_at'] as String), style: const TextStyle(color: Brand.ink2, fontSize: 14)),
            if (e['venue'] != null) Text('${e['venue']}', style: const TextStyle(color: Brand.ink2, fontSize: 14)),
            if (e['nekath'] != null) ...[const SizedBox(height: 6), StatusTag('${e['nekath']}', Brand.accent)],
          ]),
        ),
        if (onTap != null) const Icon(Icons.edit_outlined, size: 20, color: Brand.ink2),
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

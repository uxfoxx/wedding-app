import 'package:flutter/material.dart';

import '../ui.dart';
import 'plan_tab.dart';

/// "Your wedding is 70% ready" with the three next steps.
class ReadinessCard extends StatefulWidget {
  const ReadinessCard({super.key, this.onGo});
  final void Function(String key)? onGo;
  @override
  State<ReadinessCard> createState() => _ReadinessCardState();
}

class _ReadinessCardState extends State<ReadinessCard> {
  Map<String, dynamic>? r;
  String? key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    final k = '${s.weddingId}:${s.summary?['counts']}';
    if (k != key) {
      key = k;
      s.api.get('/weddings/${s.weddingId}/readiness').then((v) {
        if (mounted) setState(() => r = v);
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (r == null) return const SizedBox.shrink();
    final th = Theme.of(context);
    final score = r!['score'] as int;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(width: 72, height: 72, child: CircularProgressIndicator(value: score / 100, strokeWidth: 7, backgroundColor: th.colorScheme.surfaceContainerHighest)),
              Text('$score%', style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your wedding is $score% ready', style: th.textTheme.titleMedium),
              const SizedBox(height: 4),
              for (final n in r!['next'] as List)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: InkWell(
                    onTap: widget.onGo == null ? null : () => widget.onGo!(n['key'] as String),
                    child: Row(children: [const Icon(Icons.arrow_right, size: 20), Expanded(child: Text(n['label'] as String))]),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Tasks (kind=task) and the suggested checklist (kind=checklist).
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, required this.kind});
  final String kind;
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<dynamic>? tasks;
  List<dynamic> members = [];

  String get base => '/weddings/${AppScope.read(context).weddingId}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final s = AppScope.read(context);
    final r = await guard(context, () => s.api.get('$base/tasks', {'kind': widget.kind}));
    final m = await s.api.get('$base/members').catchError((_) => <String, dynamic>{'members': []});
    if (r != null && mounted) setState(() { tasks = r['tasks'] as List<dynamic>; members = m['members'] as List<dynamic>; });
  }

  Future<void> add() async {
    final s = AppScope.read(context);
    final title = TextEditingController();
    String? assignee;
    String? due;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(widget.kind == 'checklist' ? 'Add to checklist' : 'New task'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'What needs doing')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue: assignee,
              decoration: const InputDecoration(labelText: 'Who'),
              items: [const DropdownMenuItem(value: null, child: Text('No one yet')), for (final m in members) DropdownMenuItem(value: m['id'] as String, child: Text((m['name'] ?? m['email'] ?? m['phone']) as String))],
              onChanged: (v) => set(() => assignee = v),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(due ?? 'Due date'),
              onPressed: () async {
                final d = await showDatePicker(context: c, firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime(DateTime.now().year + 4), initialDate: DateTime.now().add(const Duration(days: 7)));
                if (d != null) set(() => due = d.toIso8601String().substring(0, 10));
              },
            ),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add'))],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty || !mounted) return;
    await guard(context, () => s.api.post('$base/tasks', {'title': title.text.trim(), 'kind': widget.kind, 'assignee_id': assignee, 'due_date': due}));
    await load();
  }

  String bucket(dynamic m) => m == null ? 'Other' : (m as int) < 0 ? 'After the wedding' : m == 0 ? 'The last weeks' : '$m month${m == 1 ? '' : 's'} before';

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    final isChecklist = widget.kind == 'checklist';
    final title = isChecklist ? 'Checklist' : 'Tasks';
    if (tasks == null) return Scaffold(appBar: AppBar(title: Text(title)), body: const Center(child: CircularProgressIndicator()));
    final done = tasks!.where((t) => t['done_at'] != null).length;
    String? last;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (s.isPlanner && s.wedding['planner_id'] != null && tasks!.isNotEmpty && isChecklist)
            IconButton(
              tooltip: 'Save as template',
              icon: const Icon(Icons.bookmark_add_outlined),
              onPressed: () async {
                final r = await guard(context, () => s.api.post('/planner/templates', {'kind': 'checklist', 'name': 'Checklist from ${s.wedding['partner1']} & ${s.wedding['partner2']}', 'from_wedding_id': s.weddingId}));
                if (r != null && context.mounted) toast(context, 'Saved to your templates');
              },
            ),
        ],
      ),
      floatingActionButton: s.canEditAll && tasks!.isNotEmpty ? FloatingActionButton(onPressed: add, tooltip: 'Add', child: const Icon(Icons.add)) : null,
      body: RefreshIndicator(
        onRefresh: load,
        child: PageBody(children: [
          if (tasks!.isEmpty)
            isChecklist
                ? EmptyState(
                    icon: Icons.checklist,
                    title: 'Start with our suggested checklist',
                    body: 'Tasks for a ${s.wedding['wedding_type'] ?? ''} wedding in Sri Lanka, from booking the venue to thank-you messages, timed to your date.',
                    action: 'Add suggested tasks',
                    onAction: () async {
                      await guard(context, () => s.api.post('$base/checklist/suggest'));
                      await load();
                    },
                  )
                : EmptyState(icon: Icons.task_alt, title: 'No tasks', body: 'Add to-dos with a due date and who is doing them.', action: 'New task', onAction: add)
          else ...[
            if (isChecklist) ...[
              LinearProgressIndicator(value: done / tasks!.length),
              const SizedBox(height: 4),
              Text('$done of ${tasks!.length} done'),
            ],
            for (final t in tasks!) ...[
              if (isChecklist && bucket(t['months_before']) != last) ...[
                Builder(builder: (_) { last = bucket(t['months_before']); return const SizedBox.shrink(); }),
                Padding(padding: const EdgeInsets.only(top: 16, bottom: 4), child: Text(bucket(t['months_before']), style: th.textTheme.titleSmall)),
              ],
              Card(
                child: CheckboxListTile(
                  value: t['done_at'] != null,
                  onChanged: s.canEditAll
                      ? (v) async {
                          await guard(context, () => s.api.patch('$base/tasks/${t['id']}', {'done': v}));
                          await load();
                        }
                      : null,
                  title: Text(t['title'] as String, style: t['done_at'] != null ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
                  subtitle: (t['due_date'] != null || t['assignee_name'] != null)
                      ? Text([if (t['due_date'] != null) 'due ${'${t['due_date']}'.substring(0, 10)}', if (t['assignee_name'] != null) '${t['assignee_name']}'].join(' · '),
                          style: TextStyle(color: t['done_at'] == null && t['due_date'] != null && '${t['due_date']}'.substring(0, 10).compareTo(today) < 0 ? th.colorScheme.error : null))
                      : null,
                  secondary: s.canEditAll
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete',
                          onPressed: () async {
                            await guard(context, () => s.api.delete('$base/tasks/${t['id']}'));
                            await load();
                          },
                        )
                      : null,
                ),
              ),
            ],
          ],
          const SizedBox(height: 80),
        ]),
      ),
    );
  }
}

class RunSheetScreen extends StatefulWidget {
  const RunSheetScreen({super.key});
  @override
  State<RunSheetScreen> createState() => _RunSheetScreenState();
}

class _RunSheetScreenState extends State<RunSheetScreen> {
  List<dynamic>? items;
  String get base => '/weddings/${AppScope.read(context).weddingId}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final r = await guard(context, () => AppScope.read(context).api.get('$base/run-sheet'));
    if (r != null && mounted) setState(() => items = r['items'] as List<dynamic>);
  }

  Future<void> edit([Map<String, dynamic>? it]) async {
    final s = AppScope.read(context);
    final events = (s.summary?['events'] as List?) ?? [];
    final time = TextEditingController(text: it?['time'] ?? '');
    final what = TextEditingController(text: it?['item'] ?? '');
    final who = TextEditingController(text: it?['owner'] ?? '');
    final notes = TextEditingController(text: it?['notes'] ?? '');
    String? eventId = it?['event_id'] as String? ?? (events.isNotEmpty ? events.first['id'] as String : null);
    final r = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(it == null ? 'Add to run sheet' : 'Run sheet item'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (events.length > 1 && it == null)
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: eventId,
                  decoration: const InputDecoration(labelText: 'Event'),
                  items: [for (final e in events) DropdownMenuItem(value: e['id'] as String, child: Text((e['title'] ?? eventKinds[e['kind']]) as String))],
                  onChanged: (v) => set(() => eventId = v),
                ),
              const SizedBox(height: 8),
              TextField(controller: time, decoration: const InputDecoration(labelText: 'Time', hintText: '10:24')),
              const SizedBox(height: 8),
              TextField(controller: what, decoration: const InputDecoration(labelText: 'What happens', hintText: 'Poruwa ceremony')),
              const SizedBox(height: 8),
              TextField(controller: who, decoration: const InputDecoration(labelText: 'Who is responsible', hintText: 'Kapuwa, MC, photographer…')),
              const SizedBox(height: 8),
              TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
            ]),
          ),
          actions: [
            if (it != null) TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Delete')),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (!mounted || r == null) return;
    if (r == 'delete') {
      await guard(context, () => s.api.delete('$base/run-sheet/${it!['id']}'));
    } else if (time.text.trim().isNotEmpty && what.text.trim().isNotEmpty) {
      final body = {'time': time.text.trim(), 'item': what.text.trim(), 'owner': who.text.trim(), 'notes': notes.text.trim()};
      await guard(context, () => it == null ? s.api.post('$base/run-sheet', {...body, 'event_id': eventId}) : s.api.patch('$base/run-sheet/${it['id']}', body));
    }
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final events = {for (final e in (s.summary?['events'] as List?) ?? []) e['id']: e};
    String? last;
    return Scaffold(
      appBar: AppBar(title: const Text('Run sheet'), actions: [
        IconButton(
          tooltip: 'Print / share',
          icon: const Icon(Icons.print_outlined),
          onPressed: () async {
            final r = await guard(context, () => s.api.post('$base/report-link', {'kind': 'run_sheet'}));
            if (r != null) await openUrl(r['url'] as String, inApp: true);
          },
        ),
      ]),
      floatingActionButton: s.canEditAll && (items?.isNotEmpty ?? false) ? FloatingActionButton(onPressed: () => edit(), child: const Icon(Icons.add)) : null,
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : PageBody(children: [
              if (items!.isEmpty)
                EmptyState(icon: Icons.schedule, title: 'Plan the day minute by minute', body: 'Times, what happens and who is responsible: shared with your planner and family, and printable for suppliers.', action: 'Add first item', onAction: () => edit()),
              for (final it in items!) ...[
                if (it['event_id'] != last && events[it['event_id']] != null) ...[
                  Builder(builder: (_) { last = it['event_id'] as String?; return const SizedBox.shrink(); }),
                  Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text((events[it['event_id']]['title'] ?? eventKinds[events[it['event_id']]['kind']]) as String, style: Theme.of(context).textTheme.titleMedium)),
                ],
                Card(
                  child: ListTile(
                    leading: SizedBox(width: 64, child: Text(it['time'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
                    title: Text(it['item'] as String),
                    subtitle: (it['owner'] ?? '').toString().isNotEmpty || (it['notes'] ?? '').toString().isNotEmpty ? Text([it['owner'], it['notes']].where((x) => x != null && '$x'.isNotEmpty).join(' · ')) : null,
                    onTap: s.canEditAll ? () => edit(it as Map<String, dynamic>) : null,
                  ),
                ),
              ],
              const SizedBox(height: 80),
            ]),
    );
  }
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    Future<void> open(String kind) async {
      final r = await guard(context, () => s.api.post('/weddings/${s.weddingId}/report-link', {'kind': kind}));
      if (r != null) await openUrl(r['url'] as String, inApp: true);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: PageBody(children: [
        const Text('Each report opens as a page you can print or save as PDF. Sinhala and Tamil print correctly.'),
        const SizedBox(height: 8),
        for (final r in const [
          ('guests', Icons.people_outline, 'Guest list and headcount', 'For the venue and caterer: replies, people and meals per event'),
          ('seating', Icons.table_restaurant_outlined, 'Seating plan', 'Who sits at each table'),
          ('qr_board', Icons.qr_code_2, 'Find-your-seat board', 'A–Z list with a QR code, for the venue entrance'),
          ('run_sheet', Icons.schedule, 'Run sheet', 'The wedding-day timeline for suppliers and family'),
        ])
          Card(child: ListTile(leading: Icon(r.$2), title: Text(r.$3), subtitle: Text(r.$4), trailing: const Icon(Icons.open_in_new), onTap: () => open(r.$1))),
      ]),
    );
  }
}

/// Planner-only: private client notes, contact, team assignment, ownership hand-over, templates.
class ClientNotesScreen extends StatefulWidget {
  const ClientNotesScreen({super.key});
  @override
  State<ClientNotesScreen> createState() => _ClientNotesScreenState();
}

class _ClientNotesScreenState extends State<ClientNotesScreen> {
  final notes = TextEditingController();
  final client = TextEditingController();
  final phone = TextEditingController();
  List<dynamic> team = [];
  List<dynamic> members = [];
  List<dynamic> templates = [];
  bool loaded = false;

  String get base => '/weddings/${AppScope.read(context).weddingId}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final s = AppScope.read(context);
    final r = await guard(context, () async => [
          await s.api.get('$base/planner-notes'),
          await s.api.get('/planner/team'),
          await s.api.get('$base/members'),
          await s.api.get('/planner/templates'),
        ]);
    if (r == null || !mounted) return;
    setState(() {
      notes.text = r[0]['notes'] ?? '';
      client.text = r[0]['client_name'] ?? '';
      phone.text = r[0]['client_phone'] ?? '';
      team = r[1]['team'] as List<dynamic>;
      members = r[2]['members'] as List<dynamic>;
      templates = r[3]['templates'] as List<dynamic>;
      loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    final isOwner = s.planner?['role'] == 'owner';
    final memberIds = members.map((m) => m['id']).toSet();
    final couple = members.where((m) => !team.any((t) => t['id'] == m['id'])).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Client notes and team')),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : PageBody(children: [
              TextField(controller: client, decoration: const InputDecoration(labelText: 'Client name')),
              const SizedBox(height: 12),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Client phone')),
              const SizedBox(height: 12),
              TextField(controller: notes, minLines: 4, maxLines: 12, decoration: const InputDecoration(labelText: 'Notes (only your team sees these)')),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: () async {
                    final r = await guard(context, () => s.api.patch('$base/planner-notes', {'notes': notes.text, 'client_name': client.text, 'client_phone': phone.text}));
                    if (r != null && context.mounted) toast(context, 'Saved');
                  },
                  child: const Text('Save'),
                ),
              ),
              if (isOwner) ...[
                const Divider(height: 32),
                Text('Who works on this wedding', style: th.textTheme.titleMedium),
                for (final t in team.where((t) => t['role'] != 'owner'))
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: memberIds.contains(t['id']),
                    title: Text((t['name'] ?? t['email'] ?? t['phone']) as String),
                    onChanged: (v) async {
                      await guard(context, () => s.api.post('/planner/weddings/${s.weddingId}/assign', {'user_id': t['id'], 'assigned': v}));
                      await load();
                    },
                  ),
              ],
              if (templates.isNotEmpty) ...[
                const Divider(height: 32),
                Text('Apply a template', style: th.textTheme.titleMedium),
                for (final t in templates)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t['name'] as String),
                    subtitle: Text('${t['kind']} · ${(t['items'] as List).length} items'),
                    trailing: TextButton(
                      onPressed: () async {
                        final r = await guard(context, () => s.api.post('$base/apply-template/${t['id']}'));
                        if (r != null && context.mounted) toast(context, 'Added ${r['added']} items');
                      },
                      child: const Text('Apply'),
                    ),
                  ),
              ],
              if (s.role == 'owner' && couple.isNotEmpty) ...[
                const Divider(height: 32),
                Text('Hand over to the couple', style: th.textTheme.titleMedium),
                const Text('They become the owner. You keep full edit access.'),
                for (final m in couple)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text((m['name'] ?? m['email'] ?? m['phone']) as String),
                    trailing: OutlinedButton(
                      onPressed: () async {
                        final r = await guard(context, () => s.api.post('$base/transfer-ownership', {'user_id': m['id']}));
                        if (r != null) await s.refresh();
                      },
                      child: const Text('Make owner'),
                    ),
                  ),
              ],
            ]),
    );
  }
}

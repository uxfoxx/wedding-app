import 'package:flutter/material.dart';

import '../ui.dart';
import 'settings.dart';

/// Planner workspace: all client weddings, tasks across them, team, and business settings.
class PlannerHome extends StatefulWidget {
  const PlannerHome({super.key});
  @override
  State<PlannerHome> createState() => _PlannerHomeState();
}

class _PlannerHomeState extends State<PlannerHome> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final biz = s.planner?['planner']?['business_name'] as String? ?? 'Planner';
    final tabs = <(String, IconData, Widget)>[
      ('Weddings', Icons.dashboard_outlined, const _Dashboard()),
      ('Tasks', Icons.task_alt, const _Tasks()),
      ('Team', Icons.groups_outlined, const _Team()),
      ('Business', Icons.business_outlined, const _Business()),
    ];
    final wide = isWide(context);
    final body = IndexedStack(index: index, children: [for (final t in tabs) t.$3]);
    return Scaffold(
      appBar: AppBar(
        title: Text(biz),
        actions: [
          const WorkspaceMenu(),
          IconButton(tooltip: s.t('settings'), icon: const Icon(Icons.settings_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountScreen()))),
        ],
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: index,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (i) => setState(() => index = i),
                destinations: [for (final t in tabs) NavigationRailDestination(icon: Icon(t.$2), label: Text(t.$1))],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ])
          : body,
      bottomNavigationBar: wide ? null : NavigationBar(selectedIndex: index, onDestinationSelected: (i) => setState(() => index = i), destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.$2), label: t.$1)]),
    );
  }
}

/// Switch between "My wedding", "Planner" and "Vendor" for people with more than one role.
class WorkspaceMenu extends StatelessWidget {
  const WorkspaceMenu({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final options = <(String, String)>[
      ('couple', 'My wedding'),
      if (s.isPlanner) ('planner', 'Planner'),
      if (s.isVendor) ('vendor', 'Vendor'),
    ];
    if (options.length < 2 && !s.isStaff) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'Switch role',
      icon: const Icon(Icons.swap_horiz),
      onSelected: (w) => guard(context, () => s.setWorkspace(w)),
      itemBuilder: (_) => [for (final o in options) CheckedPopupMenuItem(value: o.$1, checked: s.workspace == o.$1, child: Text(o.$2))],
    );
  }
}

class _Dashboard extends StatefulWidget {
  const _Dashboard();
  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  Map<String, dynamic>? data;
  bool showArchived = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final r = await guard(context, () => AppScope.read(context).api.get('/planner/dashboard'));
    if (r != null && mounted) setState(() => data = r);
  }

  Future<void> newWedding() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const NewClientWedding()));
    if (created == true) await load();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    if (data == null) return const Center(child: CircularProgressIndicator.adaptive());
    final all = (data!['weddings'] as List).cast<Map<String, dynamic>>();
    final list = all.where((w) => showArchived || w['archived'] != true).toList();
    final p = data!['planner'] as Map<String, dynamic>;
    return RefreshIndicator(
      onRefresh: load,
      child: PageBody(maxWidth: 1100, children: [
        if (p['approved'] != true)
          Card(color: th.colorScheme.tertiaryContainer, child: const ListTile(leading: Icon(Icons.hourglass_top), title: Text('We are checking your business'), subtitle: Text('You can run one client wedding until we approve your account (usually within a day).'))),
        Row(children: [
          Expanded(child: Semantics(header: true, child: Text('${list.length} client weddings', style: th.textTheme.titleLarge))),
          FilledButton.icon(key: const Key('newClientWedding'), onPressed: newWedding, icon: const Icon(Icons.add), label: const Text('New wedding')),
        ]),
        const SizedBox(height: 8),
        if (list.isEmpty)
          EmptyState(icon: Icons.event_available, title: 'No client weddings yet', body: 'Create a wedding for a client, invite the couple in, and run everything from here.', action: 'New wedding', onAction: newWedding),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final w in list)
            SizedBox(
              width: isWide(context) ? 340 : double.infinity,
              child: Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => guard(context, () => s.openWedding(w['id'] as String)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text('${w['partner1']} & ${w['partner2']}', style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                        _PlanChip(w),
                      ]),
                      if (w['client_name'] != null) Text('Client: ${w['client_name']}', style: th.textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Text(w['next_event'] != null ? '${fmtSl(w['next_event'] as String)} · ${w['days_to_go']} days to go' : 'No date yet'),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: (w['guests'] as int) == 0 ? 0 : (w['replied'] as int) / (w['guests'] as int)),
                      const SizedBox(height: 4),
                      Text('${w['replied']} of ${w['guests']} replied'),
                      const SizedBox(height: 4),
                      Text('${w['open_tasks']} open tasks${(w['overdue_tasks'] as int) > 0 ? ' · ${w['overdue_tasks']} overdue' : ''}',
                          style: TextStyle(color: (w['overdue_tasks'] as int) > 0 ? th.colorScheme.error : null)),
                      if ((w['team'] as List).isNotEmpty) Text('Team: ${(w['team'] as List).map((m) => m['name']).join(', ')}', style: th.textTheme.bodySmall),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
        if (all.any((w) => w['archived'] == true))
          TextButton(onPressed: () => setState(() => showArchived = !showArchived), child: Text(showArchived ? 'Hide archived weddings' : 'Show archived weddings')),
      ]),
    );
  }
}

class _PlanChip extends StatelessWidget {
  const _PlanChip(this.w);
  final Map<String, dynamic> w;
  @override
  Widget build(BuildContext context) {
    final label = w['plan'] == 'pass' ? 'Pass' : w['covered_by_studio'] == true ? 'Studio' : 'Free';
    return Chip(label: Text(label), visualDensity: VisualDensity.compact);
  }
}

class NewClientWedding extends StatefulWidget {
  const NewClientWedding({super.key});
  @override
  State<NewClientWedding> createState() => _NewClientWeddingState();
}

class _NewClientWeddingState extends State<NewClientWedding> {
  final p1 = TextEditingController(), p2 = TextEditingController(), client = TextEditingController(), phone = TextEditingController(), venue = TextEditingController();
  String type = 'buddhist';
  String language = 'en';
  DateTime? date;
  TimeOfDay time = const TimeOfDay(hour: 10, minute: 0);
  bool busy = false;

  Future<void> save() async {
    final s = AppScope.read(context);
    if (p1.text.trim().isEmpty || p2.text.trim().isEmpty) {
      toast(context, 'Add both names.');
      return;
    }
    setState(() => busy = true);
    final r = await guard(context, () => s.api.post('/planner/weddings', {
          'partner1': p1.text.trim(), 'partner2': p2.text.trim(), 'wedding_type': type, 'language': language,
          'client_name': client.text.trim(), 'client_phone': phone.text.trim(),
          if (date != null) 'event': {'starts_at': slToIso(date!, time), 'venue': venue.text.trim()},
        }));
    if (mounted) setState(() => busy = false);
    if (r != null && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New client wedding')),
      body: SafeArea(bottom: false,
        child: PageBody(maxWidth: 600, children: [
          TextField(key: const Key('cw1'), controller: p1, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Partner 1')),
          const SizedBox(height: 12),
          TextField(key: const Key('cw2'), controller: p2, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Partner 2')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'Ceremony'),
            items: const [
              DropdownMenuItem(value: 'buddhist', child: Text('Buddhist (Poruwa)')), DropdownMenuItem(value: 'hindu', child: Text('Hindu (Kovil)')),
              DropdownMenuItem(value: 'christian', child: Text('Christian (Church)')), DropdownMenuItem(value: 'muslim', child: Text('Muslim (Nikah)')),
              DropdownMenuItem(value: 'civil', child: Text('Civil')), DropdownMenuItem(value: 'mixed', child: Text('Mixed / other')),
            ],
            onChanged: (v) => setState(() => type = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: language,
            decoration: const InputDecoration(labelText: 'Invitation language'),
            items: const [DropdownMenuItem(value: 'en', child: Text('English')), DropdownMenuItem(value: 'si', child: Text('සිංහල')), DropdownMenuItem(value: 'ta', child: Text('தமிழ்'))],
            onChanged: (v) => setState(() => language = v!),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(date == null ? 'Date (optional)' : '${date!.day}/${date!.month}/${date!.year}'),
                onPressed: () async {
                  final d = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime(DateTime.now().year + 4), initialDate: date ?? DateTime.now().add(const Duration(days: 180)));
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
          TextField(controller: venue, decoration: const InputDecoration(labelText: 'Venue')),
          const SizedBox(height: 20),
          Text('Client contact (only your team sees this)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(controller: client, decoration: const InputDecoration(labelText: 'Client name')),
          const SizedBox(height: 12),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Client phone')),
          const SizedBox(height: 20),
          FilledButton(key: const Key('cwSave'), onPressed: busy ? null : save, child: const Text('Create wedding')),
        ]),
      ),
    );
  }
}

class _Tasks extends StatefulWidget {
  const _Tasks();
  @override
  State<_Tasks> createState() => _TasksState();
}

class _TasksState extends State<_Tasks> {
  List<dynamic>? tasks;
  bool mine = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final r = await guard(context, () => AppScope.read(context).api.get('/planner/tasks', {'mine': '$mine'}));
    if (r != null && mounted) setState(() => tasks = r['tasks'] as List<dynamic>);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return RefreshIndicator(
      onRefresh: load,
      child: PageBody(maxWidth: 900, children: [
        SegmentedButton<bool>(
          segments: const [ButtonSegment(value: true, label: Text('My tasks')), ButtonSegment(value: false, label: Text('Everyone'))],
          selected: {mine},
          onSelectionChanged: (v) {
            setState(() => mine = v.first);
            load();
          },
        ),
        const SizedBox(height: 8),
        if (tasks == null) const Center(child: CircularProgressIndicator.adaptive()),
        if (tasks != null && tasks!.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Nothing open. Add tasks inside a client wedding (Plan → Tasks).')),
        for (final t in tasks ?? [])
          Card(
            child: CheckboxListTile(
              value: false,
              onChanged: (_) async {
                await guard(context, () => s.api.patch('/weddings/${t['wedding_id']}/tasks/${t['id']}', {'done': true}));
                await load();
              },
              title: Text(t['title'] as String),
              subtitle: Text([
                '${t['partner1']} & ${t['partner2']}',
                if (t['due_date'] != null) 'due ${'${t['due_date']}'.substring(0, 10)}',
                if (t['assignee_name'] != null) '${t['assignee_name']}',
              ].join(' · '), style: TextStyle(color: t['due_date'] != null && '${t['due_date']}'.substring(0, 10).compareTo(today) < 0 ? th.colorScheme.error : null)),
            ),
          ),
      ]),
    );
  }
}

class _Team extends StatefulWidget {
  const _Team();
  @override
  State<_Team> createState() => _TeamState();
}

class _TeamState extends State<_Team> {
  Map<String, dynamic>? data;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final r = await guard(context, () => AppScope.read(context).api.get('/planner/team'));
    if (r != null && mounted) setState(() => data = r);
  }

  Future<void> invite() async {
    final s = AppScope.read(context);
    final r = await guard(context, () => s.api.post('/planner/team/invite'));
    if (r == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Invite a team member'),
        content: SelectableText(r['message'] as String),
        actions: [
          TextButton(onPressed: () => copy(c, r['message'] as String, 'Copied'), child: const Text('Copy')),
          FilledButton(onPressed: () => openUrl('https://wa.me/?text=${Uri.encodeComponent(r['message'] as String)}'), child: const Text('WhatsApp')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final isOwner = s.planner?['role'] == 'owner';
    if (data == null) return const Center(child: CircularProgressIndicator.adaptive());
    final limit = data!['limit'];
    return PageBody(children: [
      Semantics(header: true, child: Text('Team', style: Theme.of(context).textTheme.titleLarge)),
      Text(limit == null || (limit is num && limit > 1000) ? 'Unlimited team members (Studio).' : 'Your plan includes up to $limit team member${limit == 1 ? '' : 's'}.'),
      const SizedBox(height: 8),
      for (final m in data!['team'] as List)
        Card(
          child: ListTile(
            leading: Icon(m['role'] == 'owner' ? Icons.star_outline : Icons.person_outline),
            title: Text((m['name'] ?? m['email'] ?? m['phone'] ?? '') as String),
            subtitle: Text('${m['role'] == 'owner' ? 'Owner' : 'Coordinator'} · ${m['weddings']} weddings'),
            trailing: isOwner && m['role'] != 'owner'
                ? IconButton(
                    tooltip: 'Remove from team',
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: () async {
                      await guard(context, () => s.api.delete('/planner/team/${m['id']}'));
                      await load();
                    },
                  )
                : null,
          ),
        ),
      if (isOwner) OutlinedButton.icon(onPressed: invite, icon: const Icon(Icons.group_add_outlined), label: const Text('Invite a coordinator')),
      const SizedBox(height: 12),
      const Text('Coordinators see only the weddings you assign to them. Assign people from a wedding\'s Plan tab.'),
    ]);
  }
}

class _Business extends StatefulWidget {
  const _Business();
  @override
  State<_Business> createState() => _BusinessState();
}

class _BusinessState extends State<_Business> {
  List<dynamic>? templates;
  late final p = AppScope.read(context).planner?['planner'] as Map<String, dynamic>? ?? {};
  late final name = TextEditingController(text: p['business_name'] ?? '');
  late final phone = TextEditingController(text: p['phone'] ?? '');
  late final logo = TextEditingController(text: p['logo_url'] ?? '');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final r = await guard(context, () => AppScope.read(context).api.get('/planner/templates'));
    if (r != null && mounted) setState(() => templates = r['templates'] as List<dynamic>);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    final info = s.planner ?? {};
    final isOwner = info['role'] == 'owner';
    final plan = p['plan'] as String? ?? 'free';
    return PageBody(children: [
      Semantics(header: true, child: Text('Business profile', style: th.textTheme.titleLarge)),
      const SizedBox(height: 8),
      TextField(controller: name, enabled: isOwner, decoration: const InputDecoration(labelText: 'Business name')),
      const SizedBox(height: 12),
      TextField(controller: phone, enabled: isOwner, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
      const SizedBox(height: 12),
      TextField(controller: logo, enabled: isOwner, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Logo link (https://…)', helperText: 'Shown on invitations and reports with the Studio plan')),
      const SizedBox(height: 12),
      if (isOwner)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: () async {
              final r = await guard(context, () => s.api.patch('/planner', {'business_name': name.text, 'phone': phone.text, 'logo_url': logo.text}));
              if (r != null) {
                await s.loadPlanner();
                if (context.mounted) toast(context, 'Saved');
              }
            },
            child: const Text('Save'),
          ),
        ),
      const Divider(height: 32),
      Semantics(header: true, child: Text('Plan', style: th.textTheme.titleLarge)),
      Text(switch (plan) {
        'studio10' => 'Studio 10: up to 10 new weddings a month${info['studioActive'] == true ? '' : ' (expired)'}',
        'studio_unlimited' => 'Studio Unlimited${info['studioActive'] == true ? '' : ' (expired)'}',
        _ => 'Free: one unpaid wedding at a time. Each further wedding needs its Wedding Pass (you or the couple can pay).',
      }),
      const SizedBox(height: 4),
      const Text('Studio (10 or unlimited weddings a month, unlimited team, your logo) is billed monthly. Contact us to start it.'),
      const Divider(height: 32),
      Semantics(header: true, child: Text('Reusable templates', style: th.textTheme.titleLarge)),
      const Text('Save a checklist, run sheet or budget from any wedding (Plan tab → Save as template), then apply it to new weddings.'),
      for (final t in templates ?? [])
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(switch (t['kind']) { 'checklist' => Icons.checklist, 'run_sheet' => Icons.schedule, _ => Icons.payments_outlined }),
          title: Text(t['name'] as String),
          subtitle: Text('${t['kind']} · ${(t['items'] as List).length} items'),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await guard(context, () => s.api.delete('/planner/templates/${t['id']}'));
              await load();
            },
          ),
        ),
    ]);
  }
}

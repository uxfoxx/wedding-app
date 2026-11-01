import 'package:flutter/material.dart';

import '../ui.dart';

/// Admin console (staff role). Same app and web panel; every change is audited on the server.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? stats;
  List<dynamic> pending = [];
  List<dynamic> designJobs = [];
  Map<String, dynamic>? results;
  final search = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (stats == null) load();
  }

  Future<void> load() async {
    final s = AppScope.read(context);
    final r = await guard(context, () async => [
          await s.api.get('/admin/stats'),
          await s.api.get('/admin/payments', {'status': 'pending'}),
          await s.api.get('/admin/design-jobs').catchError((_) => <String, dynamic>{'jobs': []}),
        ]);
    if (r != null && mounted) {
      setState(() {
        stats = r[0];
        pending = (r[1]['payments'] as List).where((p) => p['method'] == 'bank_transfer').toList();
        designJobs = r[2]['jobs'] as List<dynamic>;
      });
    }
  }

  Future<String?> askReason(String title) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Reason (kept in the audit log)')),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    final gate = stats?['phase1Gate'];
    final days = (stats?['days'] as List?) ?? [];
    return Scaffold(
      appBar: AppBar(title: Text(s.t('admin')), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
      body: stats == null
          ? const Center(child: CircularProgressIndicator())
          : PageBody(maxWidth: 1100, children: [
              Text('Phase 1 gate', style: th.textTheme.titleLarge),
              Wrap(spacing: 8, children: [
                SizedBox(width: 220, child: StatTile('Weddings that sent (target ${gate['weddingsSent']['target']})', gate['weddingsSent']['now'])),
                SizedBox(width: 220, child: StatTile('Paid weddings (target ${gate['paid']['target']})', gate['paid']['now'])),
                SizedBox(width: 220, child: StatTile('Pending transfers', stats!['totals']['pending_transfers'])),
                SizedBox(width: 220, child: StatTile('Failed jobs', stats!['totals']['failed_jobs'], color: (stats!['totals']['failed_jobs'] as int) > 0 ? th.colorScheme.error : null)),
              ]),
              const SizedBox(height: 16),
              Text('Last 14 days', style: th.textTheme.titleMedium),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(columns: const [
                  DataColumn(label: Text('Day')), DataColumn(label: Text('Sign-ups'), numeric: true), DataColumn(label: Text('Weddings'), numeric: true),
                  DataColumn(label: Text('Paid'), numeric: true), DataColumn(label: Text('Invites sent'), numeric: true), DataColumn(label: Text('RSVPs'), numeric: true),
                ], rows: [
                  for (final d in days)
                    DataRow(cells: [
                      DataCell(Text('${d['day']}'.substring(0, 10))), DataCell(Text('${d['signups']}')), DataCell(Text('${d['weddings']}')),
                      DataCell(Text('${d['paid']}')), DataCell(Text('${d['invitations_sent']}')), DataCell(Text('${d['rsvps']}')),
                    ]),
                ]),
              ),
              const Divider(height: 32),
              Text('Queues', style: th.textTheme.titleLarge),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final q in [
                  ('Planners to approve', Icons.business_center_outlined, 'planners', stats!['totals']['pending_planners']),
                  ('Vendors to check', Icons.storefront_outlined, 'vendors', null),
                  ('Vendor complaints', Icons.report_outlined, 'complaints', null),
                  ('Reported photos & messages', Icons.flag_outlined, 'reports', stats!['totals']['open_reports']),
                ])
                  ActionChip(avatar: Icon(q.$2, size: 18), label: Text('${q.$1}${q.$4 != null ? ' (${q.$4})' : ''}'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminQueue(kind: q.$3)))),
              ]),
              const Divider(height: 32),
              Text('Bank transfers to confirm', style: th.textTheme.titleLarge),
              if (pending.isEmpty) const Text('None waiting.'),
              for (final p in pending)
                Card(
                  child: ListTile(
                    title: Text('${p['reference']} · LKR ${p['amount_lkr']}'),
                    subtitle: Text('${p['partner1']} & ${p['partner2']} · ${p['email'] ?? ''}'),
                    trailing: FilledButton(
                      onPressed: () async {
                        await guard(context, () => s.api.post('/admin/payments/${p['id']}/approve'));
                        await load();
                      },
                      child: const Text('Confirm'),
                    ),
                  ),
                ),
              const Divider(height: 32),
              Text('Look up', style: th.textTheme.titleLarge),
              TextField(
                controller: search,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Email, phone, name, payment reference'),
                onSubmitted: (v) async {
                  final r = await guard(context, () => s.api.get('/admin/search', {'q': v}));
                  if (r != null) setState(() => results = r);
                },
              ),
              if (results != null) ...[
                for (final u in results!['users'] as List)
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text('${u['email'] ?? u['phone'] ?? u['id']}'),
                    subtitle: Text(u['blocked_at'] != null ? 'Blocked' : (u['staff_role'] ?? 'User')),
                    trailing: TextButton(
                      onPressed: () async {
                        final reason = await askReason(u['blocked_at'] != null ? 'Unblock user' : 'Block user');
                        if (reason == null || reason.isEmpty || !context.mounted) return;
                        await guard(context, () => s.api.post('/admin/users/${u['id']}/block', {'blocked': u['blocked_at'] == null, 'reason': reason}));
                      },
                      child: Text(u['blocked_at'] != null ? 'Unblock' : 'Block'),
                    ),
                  ),
                for (final w in results!['weddings'] as List)
                  ListTile(
                    leading: const Icon(Icons.favorite_outline),
                    title: Text('${w['partner1']} & ${w['partner2']}'),
                    subtitle: Text('${w['plan']}'),
                    trailing: Wrap(children: [
                      if (w['plan'] != 'pass')
                        TextButton(
                          onPressed: () async {
                            final reason = await askReason('Give a free Wedding Pass');
                            if (reason == null || reason.isEmpty || !context.mounted) return;
                            await guard(context, () => s.api.post('/admin/weddings/${w['id']}/grant-pass', {'reason': reason}));
                          },
                          child: const Text('Grant pass'),
                        ),
                      TextButton(
                        onPressed: () async {
                          final reason = await askReason('Take the guest page down');
                          if (reason == null || reason.isEmpty || !context.mounted) return;
                          await guard(context, () => s.api.post('/admin/weddings/${w['id']}/takedown', {'reason': reason}));
                        },
                        child: const Text('Take down'),
                      ),
                    ]),
                  ),
                for (final p in results!['payments'] as List)
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text('${p['reference']} · LKR ${p['amount_lkr']} · ${p['status']}'),
                    trailing: p['status'] == 'paid'
                        ? TextButton(
                            onPressed: () async {
                              final reason = await askReason('Refund');
                              if (reason == null || reason.isEmpty || !context.mounted) return;
                              await guard(context, () => s.api.post('/admin/payments/${p['id']}/refund', {'reason': reason}));
                            },
                            child: const Text('Refund'),
                          )
                        : null,
                  ),
              ],
              const Divider(height: 32),
              Text('"Design it for me" jobs', style: th.textTheme.titleLarge),
              if (designJobs.isEmpty) const Text('None yet.'),
              for (final j in designJobs)
                Card(
                  child: ListTile(
                    title: Text('${j['partner1']} & ${j['partner2']} · ${j['status']}'),
                    subtitle: Text('${j['brief']['style'] ?? ''} ${j['brief']['notes'] ?? ''}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (st) async {
                        await guard(context, () => s.api.patch('/admin/design-jobs/${j['id']}', {'status': st}));
                        await load();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'queued', child: Text('Queued')),
                        PopupMenuItem(value: 'in_progress', child: Text('In progress')),
                        PopupMenuItem(value: 'review', child: Text('Ready for couple to review')),
                        PopupMenuItem(value: 'cancelled', child: Text('Cancelled')),
                      ],
                    ),
                  ),
                ),
            ]),
    );
  }
}


/// Admin queues: planners, vendors (checks → approve), complaints, reported content.
class AdminQueue extends StatefulWidget {
  const AdminQueue({super.key, required this.kind});
  final String kind;
  @override
  State<AdminQueue> createState() => _AdminQueueState();
}

class _AdminQueueState extends State<AdminQueue> {
  List<dynamic>? items;
  List<dynamic> extra = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final s = AppScope.read(context);
    final r = await guard(context, () => switch (widget.kind) {
          'planners' => s.api.get('/admin/planners', {'status': 'pending'}),
          'vendors' => s.api.get('/admin/vendors', {'status': 'pending'}),
          'complaints' => s.api.get('/admin/vendor-complaints'),
          _ => s.api.get('/admin/reports'),
        });
    if (r == null || !mounted) return;
    setState(() {
      items = (r['planners'] ?? r['vendors'] ?? r['complaints'] ?? r['uploads']) as List<dynamic>;
      extra = (r['guestbook'] as List?) ?? [];
    });
  }

  Future<String?> reason() async {
    final c = TextEditingController();
    return showDialog<String>(context: context, builder: (d) => AlertDialog(title: const Text('Reason (audit log)'), content: TextField(controller: c), actions: [FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('OK'))]));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    Future<void> act(Future<dynamic> Function() f) async {
      await guard(context, f);
      await load();
    }

    final title = {'planners': 'Planners to approve', 'vendors': 'Vendors to check', 'complaints': 'Vendor complaints', 'reports': 'Reported content'}[widget.kind]!;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : PageBody(maxWidth: 1000, children: [
              if (items!.isEmpty && extra.isEmpty) const Text('Nothing waiting.'),
              for (final x in items!)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: switch (widget.kind) {
                      'planners' => ListTile(
                          title: Text(x['business_name'] as String),
                          subtitle: Text('${x['email'] ?? ''} · ${x['phone'] ?? ''} · ${x['district'] ?? ''} · ${x['weddings']} weddings'),
                          trailing: FilledButton(onPressed: () => act(() => s.api.post('/admin/planners/${x['id']}/approve')), child: const Text('Approve')),
                        ),
                      'vendors' => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${x['business_name']} · ${x['category']} · ${x['district']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${x['owner_email'] ?? ''} · ${x['phone'] ?? ''} · ${x['media']} photos · ${x['packages']} packages'),
                          Wrap(spacing: 6, children: [
                            for (final c in const [('phone_verified', 'Phone verified'), ('registration_checked', 'Registration / NIC'), ('portfolio_checked', 'Original portfolio')])
                              FilterChip(label: Text(c.$2), selected: x[c.$1] == true, onSelected: (v) => act(() => s.api.post('/admin/vendors/${x['id']}/checks', {c.$1: v}))),
                          ]),
                          Row(children: [
                            FilledButton(
                              onPressed: () async {
                                final r = await reason();
                                if (r != null && r.isNotEmpty) await act(() => s.api.post('/admin/vendors/${x['id']}/status', {'status': 'approved', 'reason': r}));
                              },
                              child: const Text('Approve'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () async {
                                final r = await reason();
                                if (r != null && r.isNotEmpty) await act(() => s.api.post('/admin/vendors/${x['id']}/status', {'status': 'draft', 'reason': r}));
                              },
                              child: const Text('Send back'),
                            ),
                          ]),
                        ]),
                      'complaints' => ListTile(
                          title: Text('${x['business_name']}: from ${x['partner1']} & ${x['partner2']}'),
                          subtitle: Text(x['body'] as String),
                          trailing: Wrap(children: [
                            TextButton(onPressed: () => act(() => s.api.post('/admin/vendor-complaints/${x['id']}', {'status': 'upheld'})), child: const Text('Uphold')),
                            TextButton(onPressed: () => act(() => s.api.post('/admin/vendor-complaints/${x['id']}', {'status': 'dismissed'})), child: const Text('Dismiss')),
                          ]),
                        ),
                      _ => ListTile(
                          leading: x['kind'] == 'photo' ? Image.network(x['url'] as String, width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.image)) : const Icon(Icons.videocam),
                          title: Text('${x['partner1']} & ${x['partner2']} · by ${x['uploader'] ?? 'guest'}'),
                          trailing: Wrap(children: [
                            TextButton(onPressed: () => act(() => s.api.post('/admin/reports/resolve', {'kind': 'upload', 'id': x['id'], 'action': 'restore'})), child: const Text('Restore')),
                            TextButton(onPressed: () => act(() => s.api.post('/admin/reports/resolve', {'kind': 'upload', 'id': x['id'], 'action': 'remove'})), child: const Text('Remove')),
                          ]),
                        ),
                    },
                  ),
                ),
              for (final g in extra)
                Card(
                  child: ListTile(
                    title: Text('Guestbook: ${g['name']} (${g['partner1']} & ${g['partner2']})'),
                    subtitle: Text(g['message'] as String? ?? 'Voice note'),
                    trailing: Wrap(children: [
                      TextButton(onPressed: () => act(() => s.api.post('/admin/reports/resolve', {'kind': 'guestbook', 'id': g['id'], 'action': 'restore'})), child: const Text('Restore')),
                      TextButton(onPressed: () => act(() => s.api.post('/admin/reports/resolve', {'kind': 'guestbook', 'id': g['id'], 'action': 'remove'})), child: const Text('Remove')),
                    ]),
                  ),
                ),
            ]),
    );
  }
}

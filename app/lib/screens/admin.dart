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

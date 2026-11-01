import 'package:flutter/material.dart';

import '../ui.dart';

String lkr(num n) {
  final s = n.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return 'LKR $b';
}

const budgetCategories = ['Venue', 'Food & drinks', 'Photography', 'Decoration', 'Attire', 'Makeup & hair', 'Music', 'Transport', 'Invitations', 'Rings & jewellery', 'Ceremony', 'Honeymoon', 'Other'];

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});
  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  Map<String, dynamic>? data;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final s = AppScope.read(context);
    final r = await guard(context, () => s.api.get('/weddings/${s.weddingId}/budget'));
    if (r != null && mounted) setState(() => data = r);
  }

  Future<void> edit([Map<String, dynamic>? item]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => BudgetItemEditor(item: item)));
    if (saved == true) await load();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    if (data == null) return Scaffold(appBar: AppBar(title: const Text('Budget')), body: const Center(child: CircularProgressIndicator()));
    final t = data!['totals'] as Map<String, dynamic>;
    final items = (data!['items'] as List).cast<Map<String, dynamic>>();
    final cats = <String, List<Map<String, dynamic>>>{};
    for (final i in items) {
      cats.putIfAbsent(i['category'] as String, () => []).add(i);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Budget')),
      floatingActionButton: s.canEditAll ? FloatingActionButton.extended(onPressed: () => edit(), icon: const Icon(Icons.add), label: const Text('Add item')) : null,
      body: RefreshIndicator(
        onRefresh: load,
        child: PageBody(maxWidth: 900, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(width: 200, child: StatTile('Planned', lkr(t['estimated'] as num))),
            SizedBox(width: 200, child: StatTile('Agreed cost', lkr(t['cost'] as num))),
            SizedBox(width: 200, child: StatTile('Paid', lkr(t['paid'] as num), color: Colors.green.shade700)),
            SizedBox(width: 200, child: StatTile('Still to pay', lkr(t['due'] as num), color: (t['due'] as num) > 0 ? th.colorScheme.error : null)),
          ]),
          for (final r in data!['reminders'] as List)
            Card(
              color: r['overdue'] == true ? th.colorScheme.errorContainer : th.colorScheme.tertiaryContainer,
              child: ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: Text('${r['name']}: ${lkr(r['amount'] as num)}'),
                subtitle: Text('${r['overdue'] == true ? 'Overdue since' : 'Due'} ${'${r['due_date']}'.substring(0, 10)}${r['vendor'] != null ? ' · ${r['vendor']}' : ''}'),
              ),
            ),
          if (items.isEmpty)
            EmptyState(icon: Icons.payments_outlined, title: 'No budget yet', body: 'Add what you expect to spend on the venue, food, photography and more. Then track what is paid and due.', action: 'Add item', onAction: () => edit()),
          for (final e in cats.entries) ...[
            const SizedBox(height: 12),
            Text('${e.key} · ${lkr(e.value.fold<num>(0, (n, i) => n + ((i['total_lkr'] ?? i['estimated_lkr']) as num)))}', style: th.textTheme.titleMedium),
            for (final i in e.value)
              Card(
                child: ListTile(
                  title: Text(i['name'] as String),
                  subtitle: Text([
                    if (i['vendor'] != null) i['vendor'],
                    'paid ${lkr(i['paid_lkr'] as num)} of ${lkr((i['total_lkr'] ?? i['estimated_lkr']) as num)}',
                    if (i['due_date'] != null) 'due ${'${i['due_date']}'.substring(0, 10)}',
                  ].join(' · ')),
                  trailing: Text(lkr((i['total_lkr'] ?? i['estimated_lkr']) as num), style: const TextStyle(fontWeight: FontWeight.w600)),
                  onTap: s.canEditAll ? () => edit(i) : null,
                ),
              ),
          ],
          const SizedBox(height: 80),
        ]),
      ),
    );
  }
}

class BudgetItemEditor extends StatefulWidget {
  const BudgetItemEditor({super.key, this.item});
  final Map<String, dynamic>? item;
  @override
  State<BudgetItemEditor> createState() => _BudgetItemEditorState();
}

class _BudgetItemEditorState extends State<BudgetItemEditor> {
  late final i = widget.item ?? {};
  late String category = i['category'] as String? ?? 'Venue';
  late final name = TextEditingController(text: i['name'] ?? '');
  late final vendor = TextEditingController(text: i['vendor'] ?? '');
  late final estimated = TextEditingController(text: i['estimated_lkr'] != null ? '${i['estimated_lkr']}' : '');
  late final total = TextEditingController(text: i['total_lkr'] != null ? '${i['total_lkr']}' : '');
  late final paid = TextEditingController(text: i['paid_lkr'] != null && i['paid_lkr'] != 0 ? '${i['paid_lkr']}' : '');
  late String? due = i['due_date'] != null ? '${i['due_date']}'.substring(0, 10) : null;

  num? n(String v) => v.trim().isEmpty ? null : num.tryParse(v.replaceAll(RegExp(r'[^0-9.]'), ''));

  Future<void> save() async {
    final s = AppScope.read(context);
    final body = {'category': category, 'name': name.text.trim(), 'vendor': vendor.text.trim(), 'estimated_lkr': n(estimated.text) ?? 0, 'total_lkr': n(total.text), 'paid_lkr': n(paid.text) ?? 0, 'due_date': due};
    final r = await guard(context, () => widget.item == null ? s.api.post('/weddings/${s.weddingId}/budget', body) : s.api.patch('/weddings/${s.weddingId}/budget/${i['id']}', body));
    if (r != null && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item == null ? 'Add budget item' : 'Budget item'),
        actions: [
          if (widget.item != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await guard(context, () => s.api.delete('/weddings/${s.weddingId}/budget/${i['id']}'));
                if (context.mounted) Navigator.pop(context, true);
              },
            ),
        ],
      ),
      body: PageBody(maxWidth: 560, children: [
        DropdownButtonFormField<String>(
          initialValue: budgetCategories.contains(category) ? category : 'Other',
          decoration: const InputDecoration(labelText: 'Category'),
          items: [for (final c in budgetCategories) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => setState(() => category = v!),
        ),
        const SizedBox(height: 12),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'What', hintText: 'Reception hall')),
        const SizedBox(height: 12),
        TextField(controller: vendor, decoration: const InputDecoration(labelText: 'Supplier (optional)')),
        const SizedBox(height: 12),
        TextField(controller: estimated, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Planned amount (LKR)')),
        const SizedBox(height: 12),
        TextField(controller: total, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Agreed price (LKR), once known')),
        const SizedBox(height: 12),
        TextField(controller: paid, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Paid so far (LKR)')),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.event),
          label: Text(due == null ? 'Next payment due date (optional)' : 'Next payment due $due'),
          onPressed: () async {
            final d = await showDatePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime(DateTime.now().year + 4), initialDate: due != null ? DateTime.parse(due!) : DateTime.now());
            if (d != null) setState(() => due = d.toIso8601String().substring(0, 10));
          },
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: save, child: const Text('Save')),
      ]),
    );
  }
}

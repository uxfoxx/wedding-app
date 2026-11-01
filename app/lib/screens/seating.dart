import 'package:flutter/material.dart';

import '../ui.dart';
import 'plan_tab.dart';

/// Seating: tables per event, a suggested plan, and moving parties between tables.
/// Phone: tap a party, then tap a table. Web panel: drag parties onto tables.
class SeatingScreen extends StatefulWidget {
  const SeatingScreen({super.key});
  @override
  State<SeatingScreen> createState() => _SeatingScreenState();
}

class _SeatingScreenState extends State<SeatingScreen> {
  String? eventId;
  Map<String, dynamic>? data;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final events = (AppScope.read(context).summary?['events'] as List?) ?? [];
    if (events.isNotEmpty) eventId = events.last['id'] as String; // receptions usually come last
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  String get base => '/weddings/${AppScope.read(context).weddingId}';

  Future<void> load() async {
    if (eventId == null) return;
    final r = await guard(context, () => AppScope.read(context).api.get('$base/events/$eventId/seating'));
    if (r != null && mounted) setState(() => data = r);
  }

  int used(String tableId) => (data!['guests'] as List).where((g) => g['table_id'] == tableId).fold(0, (n, g) => n + (g['size'] as int));

  Future<void> seat(Map g, String? tableId) async {
    final s = AppScope.read(context);
    final r = await guard(context, () => s.api.put('$base/events/$eventId/seats/${g['id']}', {'table_id': tableId}));
    if (r != null) await load();
  }

  Future<void> pickTable(Map g) async {
    final tables = (data!['tables'] as List).cast<Map<String, dynamic>>();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text('Seat ${g['name']} (${g['size']})', style: Theme.of(c).textTheme.titleMedium)),
          for (final t in tables)
            ListTile(
              enabled: (t['seats'] as int) - used(t['id'] as String) >= (g['size'] as int) || g['table_id'] == t['id'],
              leading: Icon(t['shape'] == 'head' ? Icons.star_outline : Icons.circle_outlined),
              title: Text(t['name'] as String),
              subtitle: Text('${(t['seats'] as int) - used(t['id'] as String)} of ${t['seats']} free'),
              selected: g['table_id'] == t['id'],
              onTap: () => Navigator.pop(c, t['id'] as String),
            ),
          if (g['table_id'] != null) ListTile(leading: const Icon(Icons.close), title: const Text('Remove from table'), onTap: () => Navigator.pop(c, '')),
        ]),
      ),
    );
    if (choice != null) await seat(g, choice.isEmpty ? null : choice);
  }

  Future<void> addTables() async {
    final s = AppScope.read(context);
    final count = TextEditingController(text: '10');
    final seats = TextEditingController(text: '10');
    String shape = 'round';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Add tables'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'round', label: Text('Round')), ButtonSegment(value: 'long', label: Text('Long')), ButtonSegment(value: 'head', label: Text('Head'))],
              selected: {shape},
              onSelectionChanged: (v) => set(() => shape = v.first),
            ),
            const SizedBox(height: 12),
            if (shape != 'head') TextField(controller: count, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'How many tables')),
            const SizedBox(height: 12),
            TextField(controller: seats, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Seats per table')),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add'))],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await guard(context, () => s.api.post('$base/events/$eventId/tables', {'shape': shape, 'count': shape == 'head' ? 1 : int.tryParse(count.text) ?? 1, 'seats': int.tryParse(seats.text) ?? 10}));
    await load();
  }

  Future<void> suggest() async {
    final s = AppScope.read(context);
    setState(() => busy = true);
    final r = await guard(context, () => s.api.post('$base/events/$eventId/seating/suggest', {'keep_existing': true}));
    if (mounted) setState(() => busy = false);
    if (r == null || !mounted) return;
    toast(context, ['${r['placed']} parties seated.', ...(r['warnings'] as List).cast<String>()].join(' '));
    await load();
  }

  Future<void> editTable(Map t) async {
    final s = AppScope.read(context);
    final name = TextEditingController(text: t['name'] as String);
    final seats = TextEditingController(text: '${t['seats']}');
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Table'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          TextField(controller: seats, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Seats')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Delete table')),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (r == 'save' && mounted) await guard(context, () => s.api.patch('$base/tables/${t['id']}', {'name': name.text, 'seats': int.tryParse(seats.text)}));
    if (r == 'delete' && mounted) await guard(context, () => s.api.delete('$base/tables/${t['id']}'));
    await load();
  }

  Future<void> keepApart() async {
    final s = AppScope.read(context);
    final guests = (data!['guests'] as List).cast<Map<String, dynamic>>();
    String? a, b;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Keep apart'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('The suggested plan will never put these two at the same table.'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(isExpanded: true, initialValue: a, decoration: const InputDecoration(labelText: 'Guest'), items: [for (final g in guests) DropdownMenuItem(value: g['id'] as String, child: Text(g['name'] as String))], onChanged: (v) => set(() => a = v)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(isExpanded: true, initialValue: b, decoration: const InputDecoration(labelText: 'and'), items: [for (final g in guests) DropdownMenuItem(value: g['id'] as String, child: Text(g['name'] as String))], onChanged: (v) => set(() => b = v)),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save'))],
        ),
      ),
    );
    if (ok == true && a != null && b != null && mounted) {
      final r = await guard(context, () => s.api.post('$base/conflicts', {'a': a, 'b': b}));
      if (r != null && mounted) toast(context, 'Saved. Run "Suggest a plan" to apply it.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    final events = (s.summary?['events'] as List?) ?? [];
    final wide = isWide(context);
    Widget content;
    if (data == null) {
      content = const Center(child: CircularProgressIndicator());
    } else {
      final tables = (data!['tables'] as List).cast<Map<String, dynamic>>();
      final guests = (data!['guests'] as List).cast<Map<String, dynamic>>();
      final unseated = guests.where((g) => g['table_id'] == null).toList();
      final people = guests.fold<int>(0, (n, g) => n + (g['size'] as int));
      final seats = tables.fold<int>(0, (n, t) => n + (t['seats'] as int));

      Widget partyChip(Map<String, dynamic> g) {
        final chip = ActionChip(
          avatar: g['vip'] == true ? const Icon(Icons.star, size: 16, color: Brand.gold) : null,
          label: Text('${g['name']} · ${g['size']}${g['status'] == 'coming' ? '' : '?'}'),
          tooltip: g['status'] == 'coming' ? 'Confirmed' : 'Not confirmed yet (invited seats)',
          onPressed: s.canEditAll ? () => pickTable(g) : null,
        );
        return wide && s.canEditAll ? Draggable<Map<String, dynamic>>(data: g, feedback: Material(color: Colors.transparent, child: chip), childWhenDragging: Opacity(opacity: .4, child: chip), child: chip) : chip;
      }

      Widget tableCard(Map<String, dynamic> t) {
        final at = guests.where((g) => g['table_id'] == t['id']).toList();
        final free = (t['seats'] as int) - used(t['id'] as String);
        final card = Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(t['shape'] == 'head' ? Icons.star_outline : t['shape'] == 'long' ? Icons.table_bar_outlined : Icons.circle_outlined, size: 20),
                const SizedBox(width: 6),
                Expanded(child: Text(t['name'] as String, style: th.textTheme.titleMedium)),
                Text('$free free', style: TextStyle(color: free < 0 ? th.colorScheme.error : th.colorScheme.outline)),
                if (s.canEditAll) IconButton(icon: const Icon(Icons.more_vert, size: 20), tooltip: 'Edit table', onPressed: () => editTable(t)),
              ]),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final g in at) partyChip(g)]),
              if (at.isEmpty) Text(wide ? 'Drag guests here' : 'Empty', style: th.textTheme.bodySmall),
            ]),
          ),
        );
        if (!wide || !s.canEditAll) return card;
        return DragTarget<Map<String, dynamic>>(
          onWillAcceptWithDetails: (d) => d.data['table_id'] != t['id'] && free >= (d.data['size'] as int),
          onAcceptWithDetails: (d) => seat(d.data, t['id'] as String),
          builder: (c, cand, rej) => Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: cand.isNotEmpty ? th.colorScheme.primary : rej.isNotEmpty ? th.colorScheme.error : Colors.transparent, width: 2)),
            child: card,
          ),
        );
      }

      content = RefreshIndicator(
        onRefresh: load,
        child: PageBody(maxWidth: 1200, children: [
          if (events.length > 1)
            DropdownButtonFormField<String>(
              initialValue: eventId,
              decoration: const InputDecoration(labelText: 'Event'),
              items: [for (final e in events) DropdownMenuItem(value: e['id'] as String, child: Text((e['title'] ?? eventKinds[e['kind']]) as String))],
              onChanged: (v) {
                setState(() { eventId = v; data = null; });
                load();
              },
            ),
          const SizedBox(height: 8),
          Text('$people people · $seats seats · ${unseated.length} parties without a table', style: th.textTheme.titleMedium),
          if (people > seats) Text('You need ${people - seats} more seats.', style: TextStyle(color: th.colorScheme.error)),
          const SizedBox(height: 8),
          if (s.canEditAll)
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: addTables, icon: const Icon(Icons.add), label: const Text('Add tables')),
              FilledButton.icon(key: const Key('suggest'), onPressed: busy || tables.isEmpty ? null : suggest, icon: const Icon(Icons.auto_awesome), label: const Text('Suggest a plan')),
              OutlinedButton.icon(onPressed: guests.length < 2 ? null : keepApart, icon: const Icon(Icons.block), label: const Text('Keep apart')),
            ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show "Find your seat" to guests'),
            subtitle: const Text('Guests see their table on their invitation, and can search on the venue QR board.'),
            value: data!['published'] == true,
            onChanged: s.canEditAll
                ? (v) async {
                    await guard(context, () => s.api.post('$base/seating/publish', {'published': v}));
                    await load();
                  }
                : null,
          ),
          if (tables.isEmpty)
            EmptyState(icon: Icons.table_restaurant_outlined, title: 'No tables yet', body: 'Add your tables, then let the app suggest a plan: families together, elders and VIPs at the front.', action: 'Add tables', onAction: addTables)
          else ...[
            if (unseated.isNotEmpty) ...[
              Text('Not seated yet', style: th.textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final g in unseated) partyChip(g)]),
              const SizedBox(height: 12),
            ],
            GridView.count(
              crossAxisCount: wide ? 3 : 1,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: wide ? 1.6 : 2.6,
              mainAxisSpacing: 4,
              crossAxisSpacing: 8,
              children: [for (final t in tables) tableCard(t)],
            ),
          ],
        ]),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('Seating')), body: SafeArea(child: content));
  }
}

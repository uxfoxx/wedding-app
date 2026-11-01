import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../ui.dart';

class RsvpsTab extends StatefulWidget {
  const RsvpsTab({super.key, required this.onGo});
  final void Function(String key) onGo;
  @override
  State<RsvpsTab> createState() => _RsvpsTabState();
}

class _RsvpsTabState extends State<RsvpsTab> {
  Map<String, dynamic>? dash;
  List<dynamic> followUps = [];
  String? loadedKey;
  String? error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    final key = '${s.weddingId}:${s.summary?['counts']}';
    if (loadedKey != key) {
      loadedKey = key;
      load();
    }
  }

  Future<void> load() async {
    final s = AppScope.read(context);
    try {
      final d = await s.api.get('/weddings/${s.weddingId}/dashboard');
      final f = await s.api.get('/weddings/${s.weddingId}/follow-ups');
      if (mounted) setState(() { dash = d; followUps = f['guests'] as List<dynamic>; error = null; });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> export() async {
    final s = AppScope.read(context);
    final csv = await guard(context, () => s.api.getText('/weddings/${s.weddingId}/export.csv'), onUpgrade: () => widget.onGo('upgrade'));
    if (csv == null) return;
    await FilePicker.saveFile(fileName: 'guest-list.csv', bytes: Uint8List.fromList(utf8.encode(csv)), mimeType: 'text/csv');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    if (dash == null && error != null) {
      return EmptyState(icon: Icons.cloud_off, title: 'Could not load replies', body: error!, action: s.t('retry'), onAction: load);
    }
    if (dash == null) return const Center(child: CircularProgressIndicator());
    final t = dash!['totals'] as Map<String, dynamic>;
    final cols = isWide(context) ? 4 : 2;
    return RefreshIndicator(
      onRefresh: load,
      child: PageBody(maxWidth: 1000, children: [
        GridView.count(crossAxisCount: cols, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 1.9, children: [
          StatTile(s.t('invited'), t['invited']),
          StatTile(s.t('sent'), t['sent']),
          StatTile(s.t('opened'), t['opened']),
          StatTile(s.t('noReply'), (dash!['events'] as List).isEmpty ? 0 : dash!['events'][0]['pending']),
        ]),
        for (final e in dash!['events'] as List)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e['name'] as String, style: th.textTheme.titleLarge),
                Text(fmtSl(e['starts_at'] as String)),
                const SizedBox(height: 12),
                Wrap(spacing: 16, runSpacing: 8, children: [
                  _Pill(s.t('coming'), e['coming'], Colors.green.shade700),
                  _Pill(s.t('notComing'), e['declined'], th.colorScheme.error),
                  _Pill(s.t('maybe'), e['maybe'], Colors.orange.shade800),
                  _Pill(s.t('noReply'), e['pending'], th.colorScheme.outline),
                ]),
                const Divider(height: 24),
                Text('${s.t('headcount')}: ${e['headcount']}${(e['maybe_headcount'] as int) > 0 ? '  (+${e['maybe_headcount']} maybe)' : ''}', style: th.textTheme.titleMedium),
                if ((e['meals_vegetarian'] as int) + (e['meals_vegan'] as int) + (e['meals_halal'] as int) > 0)
                  Text('Meals: ${e['meals_vegetarian']} vegetarian · ${e['meals_vegan']} vegan · ${e['meals_halal']} halal'),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (followUps.isNotEmpty && s.canEditGuests)
            FilledButton.icon(onPressed: () => widget.onGo('follow_up'), icon: const Icon(Icons.notifications_active_outlined), label: Text('${s.t('remind')} (${followUps.length})')),
          OutlinedButton.icon(onPressed: export, icon: const Icon(Icons.download), label: Text(s.t('export'))),
        ]),
        if (followUps.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(s.t('followUps'), style: th.textTheme.titleMedium),
          for (final g in followUps.take(10))
            ListTile(
              leading: Icon(g['callFirst'] == true ? Icons.phone : Icons.schedule),
              title: Text(g['name'] as String),
              subtitle: Text(g['callFirst'] == true ? s.t('callFirst') : (g['opened_at'] != null ? s.t('opened') : s.t('sent'))),
              trailing: g['callFirst'] == true && g['phone'] != null ? IconButton(icon: const Icon(Icons.call), onPressed: () => openUrl('tel:${g['phone']}')) : null,
            ),
        ],
        if ((dash!['recentMessages'] as List).isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Messages from guests', style: th.textTheme.titleMedium),
          for (final m in dash!['recentMessages'] as List)
            Card(child: ListTile(leading: const Icon(Icons.format_quote), title: Text(m['message'] as String), subtitle: Text(m['name'] as String))),
        ],
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.n, this.color);
  final String label;
  final Object n;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$n', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: color)),
        Text(label),
      ]);
}

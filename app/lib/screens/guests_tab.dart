import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state.dart';

import '../ui.dart';
import 'guest_editor.dart';
import 'import_screen.dart';

String guestStatus(Map g) {
  final rs = (g['rsvps'] as List?) ?? [];
  if (rs.isNotEmpty) {
    if (rs.any((r) => r['status'] == 'coming')) return 'coming';
    if (rs.every((r) => r['status'] == 'not_coming')) return 'notComing';
    return 'maybe';
  }
  if (g['opened_at'] != null) return 'opened';
  if (g['sent_at'] != null) return 'sent';
  return 'notSent';
}

class GuestsTab extends StatefulWidget {
  const GuestsTab({super.key, required this.onGo});
  final void Function(String key) onGo;
  @override
  State<GuestsTab> createState() => GuestsTabState();
}

class GuestsTabState extends State<GuestsTab> {
  List<dynamic>? guests;
  List<dynamic> dupPairs = [];
  String filter = 'all';
  String query = '';
  String? loadedFor;
  String? error;
  /// When the list shown is the copy saved on this phone (the server couldn't be reached).
  DateTime? offlineAt;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    // Reload when the wedding changes or its counts change (e.g. after sending from another screen).
    final key = '${s.weddingId}:${s.summary?['counts']}';
    if (loadedFor != key) {
      loadedFor = key;
      load();
    }
  }

  Future<void> load() async {
    final s = AppScope.read(context);
    final id = s.weddingId!;
    final prefs = await SharedPreferences.getInstance();
    try {
      final r = await s.api.get('/weddings/$id/guests');
      final d = await s.api.get('/weddings/$id/guests/duplicates');
      await prefs.setString(AppState.offlineGuestsKey(id), jsonEncode({'at': DateTime.now().toIso8601String(), 'guests': r['guests']}));
      if (mounted) setState(() { guests = r['guests'] as List<dynamic>; dupPairs = d['pairs'] as List<dynamic>; error = null; offlineAt = null; });
    } catch (e) {
      // No connection: fall back to the last list saved on this phone, if there is one.
      final raw = prefs.getString(AppState.offlineGuestsKey(id));
      if (raw != null) {
        final c = jsonDecode(raw) as Map<String, dynamic>;
        if (mounted) setState(() { guests = c['guests'] as List<dynamic>; dupPairs = []; error = null; offlineAt = DateTime.parse(c['at'] as String); });
      } else if (mounted) {
        setState(() => error = '$e');
      }
    }
  }

  Future<void> changed() async {
    await load();
    if (mounted) await AppScope.read(context).refresh();
  }

  Future<void> openImport() async {
    final s = AppScope.read(context);
    final format = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.content_paste), title: Text(s.t('importPaste')), subtitle: Text(s.t('importPasteSub')), onTap: () => Navigator.pop(c, 'paste')),
          ListTile(leading: const Icon(Icons.table_chart_outlined), title: Text(s.t('importFile')), onTap: () => Navigator.pop(c, 'csv')),
          if (ImportScreen.contactsSupported)
            ListTile(leading: const Icon(Icons.contacts_outlined), title: Text(s.t('importContacts')), onTap: () => Navigator.pop(c, 'contacts')),
        ]),
      ),
    );
    if (format == null || !mounted) return;
    final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ImportScreen(format: format, onUpgrade: () => widget.onGo('upgrade'))));
    if (added == true) await changed();
  }

  Future<void> edit([Map<String, dynamic>? g]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => GuestEditor(guest: g, onUpgrade: () => widget.onGo('upgrade'))));
    if (saved == true) await changed();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    if (error != null) {
      return EmptyState(icon: Icons.cloud_off, title: 'Could not load guests', body: error!, action: s.t('retry'), onAction: load);
    }
    if (guests == null) return const Center(child: CircularProgressIndicator());
    if (guests!.isEmpty) {
      return EmptyState(icon: Icons.people_outline, title: s.t('emptyGuests'), body: s.t('emptyGuestsSub'), action: s.t('import'), onAction: s.canEditGuests ? openImport : () {});
    }
    final q = query.toLowerCase();
    final list = guests!.where((g) {
      final st = guestStatus(g as Map);
      final okFilter = switch (filter) { 'notSent' => st == 'notSent', 'noReply' => (g['rsvps'] as List).isEmpty, 'coming' => st == 'coming', _ => true };
      return okFilter && (q.isEmpty || (g['name'] as String).toLowerCase().contains(q) || (g['phone'] ?? '').toString().contains(q));
    }).toList();
    final seats = guests!.fold<int>(0, (a, g) => a + (g['seats'] as int));
    final limit = s.summary?['plan']?['limits']?['guests'];

    return RefreshIndicator(
      onRefresh: load,
      child: PageBody(maxWidth: 1000, children: [
        // The whole app shows its own banner when it started offline; this one covers losing the
        // connection later, on this tab only.
        if (offlineAt != null && !s.offline) ...[OfflineBanner(at: offlineAt!, onRetry: load), const SizedBox(height: 8)],
        Row(children: [
          Expanded(child: Text('${guests!.length} ${s.t('guests').toLowerCase()} · $seats ${s.t('seats').toLowerCase()}${limit != null ? ' (free plan: up to $limit)' : ''}', style: th.textTheme.titleMedium)),
        ]),
        const SizedBox(height: 8),
        if (s.canEditGuests && offlineAt == null)
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(key: const Key('sendInvites'), onPressed: () => widget.onGo('send'), icon: const Icon(Icons.send), label: Text(s.t('sendInvites'))),
            OutlinedButton.icon(key: const Key('addGuest'), onPressed: () => edit(), icon: const Icon(Icons.person_add_alt), label: Text(s.t('addGuest'))),
            OutlinedButton.icon(key: const Key('import'), onPressed: openImport, icon: const Icon(Icons.upload_file), label: Text(s.t('import'))),
          ]),
        if (dupPairs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            color: th.colorScheme.tertiaryContainer,
            child: ExpansionTile(
              leading: const Icon(Icons.content_copy),
              title: Text('${s.t('duplicates')} (${dupPairs.length})'),
              children: [
                for (final p in dupPairs)
                  ListTile(
                    title: Text('${p['a']['name']}  ↔  ${p['b']['name']}'),
                    subtitle: Text(p['reason'] == 'same_phone' ? 'Same phone number' : 'Very similar names'),
                    trailing: s.canEditGuests
                        ? TextButton(
                            onPressed: () async {
                              final r = await guard(context, () => s.api.post('/weddings/${s.weddingId}/guests/${p['a']['id']}/merge', {'other_id': p['b']['id']}));
                              if (r != null) await changed();
                            },
                            child: Text(s.t('merge')),
                          )
                        : null,
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search'), onChanged: (v) => setState(() => query = v)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final f in const [('all', 'All'), ('notSent', 'Not sent'), ('noReply', 'No reply'), ('coming', 'Coming')])
              Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(f.$2), selected: filter == f.$1, onSelected: (_) => setState(() => filter = f.$1))),
          ]),
        ),
        const SizedBox(height: 8),
        for (final g in list) _GuestRow(g: g as Map<String, dynamic>, onTap: s.canEditGuests ? () => edit(g) : null),
      ]),
    );
  }
}

class _GuestRow extends StatelessWidget {
  const _GuestRow({required this.g, this.onTap});
  final Map<String, dynamic> g;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final st = guestStatus(g);
    final cs = Theme.of(context).colorScheme;
    final (label, color) = switch (st) {
      'coming' => (s.t('coming'), Colors.green.shade700),
      'notComing' => (s.t('notComing'), cs.error),
      'maybe' => (s.t('maybe'), Colors.orange.shade800),
      'opened' => (s.t('opened'), cs.primary),
      'sent' => (s.t('sent'), cs.outline),
      _ => ('Not sent', cs.outline),
    };
    final name = [g['title'], g['name']].where((x) => x != null && '$x'.isNotEmpty).join(' ');
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Row(children: [
          Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
          if (g['vip'] == true) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.star, size: 18, color: Brand.gold)),
          if ((g['tags'] as List).contains('needs_review')) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.help_outline, size: 18)),
        ]),
        subtitle: Text([
          '${g['seats']} ${g['seats'] == 1 ? 'seat' : 'seats'}',
          if (g['phone'] != null) g['phone'],
          if (g['group_name'] != null) g['group_name'],
        ].join(' · ')),
        trailing: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

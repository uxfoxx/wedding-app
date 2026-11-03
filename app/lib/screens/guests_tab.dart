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
    final coming = guests!.where((g) => guestStatus(g as Map) == 'coming').length;

    return RefreshIndicator(
      onRefresh: load,
      color: Brand.accent,
      child: PageBody(maxWidth: 1000, padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        // The whole app shows its own banner when it started offline; this one covers losing the
        // connection later, on this tab only.
        if (offlineAt != null && !s.offline) ...[OfflineBanner(at: offlineAt!, onRetry: load), const SizedBox(height: 8)],
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Eyebrow(s.t('guests'), color: Brand.accent),
                const SizedBox(height: 6),
                Semantics(
                  header: true,
                  label: '${guests!.length} ${s.t('guests')}, $seats ${s.t('seats')}',
                  excludeSemantics: true,
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${guests!.length}', style: Brand.display(60)),
                    TextSpan(text: '  $seats ${s.t('seats').toLowerCase()}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Brand.ink2)),
                  ])),
                ),
                if (limit != null) Text('Free plan: up to $limit', style: const TextStyle(fontSize: 13.5, color: Brand.ink2)),
              ]),
            ),
            if (coming > 0) StatusTag('$coming ${s.t('coming').toLowerCase()}', Brand.success, filled: true),
          ]),
        ),
        if (s.canEditGuests && offlineAt == null) ...[
          FilledButton.icon(key: const Key('sendInvites'), onPressed: () => widget.onGo('send'), icon: const Icon(Icons.send_rounded, size: 20), label: Text(s.t('sendInvites'))),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton.icon(key: const Key('addGuest'), onPressed: () => edit(), icon: const Icon(Icons.person_add_alt_rounded, size: 20), label: Text(s.t('addGuest'), overflow: TextOverflow.ellipsis))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(key: const Key('import'), onPressed: openImport, icon: const Icon(Icons.file_download_outlined, size: 20), label: Text(s.t('import'), overflow: TextOverflow.ellipsis))),
          ]),
        ],
        if (dupPairs.isNotEmpty) ...[
          const SizedBox(height: 12),
          Panel(
            padding: EdgeInsets.zero,
            color: const Color(0xFFF6EBD6),
            borderColor: const Color(0xFFE8D3AE),
            child: ExpansionTile(
              leading: const Icon(Icons.content_copy_rounded, color: Brand.warn),
              title: Text('${s.t('duplicates')} (${dupPairs.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
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
        const SizedBox(height: 20),
        TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: s.t('searchGuests'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: const BorderSide(color: Brand.line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: const BorderSide(color: Brand.line)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: const BorderSide(color: Brand.ink, width: 1.6)),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final f in [('all', s.t('toneAll')), ('notSent', 'Not sent'), ('noReply', s.t('noReply')), ('coming', s.t('coming'))])
              Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(f.$2), selected: filter == f.$1, onSelected: (_) => setState(() => filter = f.$1))),
          ]),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('No guests match.', style: TextStyle(color: Brand.ink2))))
        else
          RowGroup(children: [for (final g in list) _GuestRow(g: g as Map<String, dynamic>, onTap: s.canEditGuests ? () => edit(g) : null)]),
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
    final (label, color) = switch (st) {
      'coming' => (s.t('coming'), Brand.success),
      'notComing' => (s.t('notComing'), Brand.accent),
      'maybe' => (s.t('maybe'), Brand.warn),
      'opened' => (s.t('opened'), Brand.gold),
      'sent' => (s.t('sent'), Brand.ink2),
      _ => ('Not sent', Brand.ink2),
    };
    final name = [g['title'], g['name']].where((x) => x != null && '$x'.isNotEmpty).join(' ');
    final detail = [
      '${g['seats']} ${g['seats'] == 1 ? 'seat' : 'seats'}',
      if (g['group_name'] != null) g['group_name'],
      if (g['phone'] != null) g['phone'],
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Monogram('${g['name']}'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                if (g['vip'] == true) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.star_rounded, size: 18, color: Brand.gold, semanticLabel: 'VIP')),
                if ((g['tags'] as List).contains('needs_review')) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.help_outline_rounded, size: 17, color: Brand.warn, semanticLabel: 'Needs review')),
              ]),
              const SizedBox(height: 2),
              Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Brand.ink2, fontSize: 13.5)),
            ]),
          ),
          const SizedBox(width: 8),
          StatusTag(label, color),
        ]),
      ),
    );
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
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

  // The printable guest list and headcount; the browser's share or print menu saves it as a PDF.
  Future<void> exportPdf() async {
    final s = AppScope.read(context);
    final r = await guard(context, () => s.api.post('/weddings/${s.weddingId}/report-link', {'kind': 'guests'}), onUpgrade: () => widget.onGo('upgrade'));
    if (r != null) await openUrl(r['url'] as String, inApp: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (dash == null && error != null) {
      return EmptyState(icon: CupertinoIcons.wifi_slash, title: 'Could not load replies', body: error!, action: s.t('retry'), onAction: load);
    }
    if (dash == null) return const LoadingList();
    final t = dash!['totals'] as Map<String, dynamic>;
    final cols = isWide(context) ? 4 : 2;
    return PageBody(title: s.t('rsvps'), onRefresh: load, maxWidth: 1000, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      StatGrid(cols: cols, children: [
        StatTile(s.t('invited'), t['invited'], icon: CupertinoIcons.person_2_fill, color: Brand.indigo),
        StatTile(s.t('sent'), t['sent'], icon: CupertinoIcons.paperplane_fill, color: Brand.blue),
        StatTile(s.t('opened'), t['opened'], icon: CupertinoIcons.envelope_open_fill, color: Brand.gold),
        StatTile(s.t('noReply'), (dash!['events'] as List).isEmpty ? 0 : dash!['events'][0]['pending'], icon: CupertinoIcons.clock_fill, color: Brand.accent),
      ]),
      for (final e in dash!['events'] as List) _EventReplies(e: e as Map<String, dynamic>),
      const SizedBox(height: 8),
      if (followUps.isNotEmpty && s.canEditGuests) ...[
        FilledButton.icon(onPressed: () => widget.onGo('follow_up'), icon: const Icon(CupertinoIcons.bell_fill, size: 19), label: Text('${s.t('remind')} (${followUps.length})')),
        const SizedBox(height: 4),
      ],
      RowGroup(header: s.t('export'), children: [
        ActionRow(icon: CupertinoIcons.table_fill, tint: Brand.green, title: s.t('export'), subtitle: 'CSV for Excel or Google Sheets', onTap: export, trailing: const Icon(CupertinoIcons.arrow_down_circle, color: Brand.accent)),
        ActionRow(icon: CupertinoIcons.doc_richtext, tint: Brand.pink, title: s.t('exportPdf'), subtitle: 'For the venue and caterer', onTap: exportPdf, trailing: const Icon(CupertinoIcons.arrow_down_circle, color: Brand.accent)),
      ]),
      if (followUps.isNotEmpty)
        RowGroup(header: s.t('followUps'), indent: 70, children: [
          for (final g in followUps.take(10))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                Monogram('${g['name']}', size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(g['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17, letterSpacing: -0.43)),
                    const SizedBox(height: 1),
                    Text(
                      g['callFirst'] == true ? s.t('callFirst') : (g['opened_at'] != null ? s.t('opened') : s.t('sent')),
                      style: TextStyle(fontSize: 15, color: g['callFirst'] == true ? Brand.accent : Brand.ink2, fontWeight: g['callFirst'] == true ? FontWeight.w600 : FontWeight.w400),
                    ),
                  ]),
                ),
                if (g['phone'] != null)
                  Semantics(
                    button: true,
                    label: 'Call ${g['name']}',
                    excludeSemantics: true,
                    child: Pressable(
                      scale: 0.88,
                      onTap: () => openUrl('tel:${g['phone']}'),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: g['callFirst'] == true ? Brand.green : Brand.green.withValues(alpha: 0.14), shape: BoxShape.circle),
                        child: Icon(CupertinoIcons.phone_fill, size: 18, color: g['callFirst'] == true ? Colors.white : Brand.success),
                      ),
                    ),
                  ),
              ]),
            ),
        ]),
      if ((dash!['recentMessages'] as List).isNotEmpty) ...[
        const SectionHeader('Messages from guests'),
        for (final m in dash!['recentMessages'] as List) _Bubble(text: m['message'] as String, name: m['name'] as String),
      ],
    ]);
  }
}

/// A guest's note, drawn as a received message bubble.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.name});
  final String text, name;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Monogram(name, size: 30),
          const SizedBox(width: 8),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(left: 12, bottom: 3), child: Text(name, style: const TextStyle(fontSize: 12, color: Brand.ink2))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: const BoxDecoration(
                  color: Color(0xFFE9E9EB),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomRight: Radius.circular(20), bottomLeft: Radius.circular(6)),
                ),
                child: Text(text, style: const TextStyle(fontSize: 17, height: 1.3, letterSpacing: -0.43)),
              ),
            ]),
          ),
          const SizedBox(width: 40),
        ]),
      );
}

/// One event's replies: a bar split by answer, the counts under it and the headcount.
class _EventReplies extends StatelessWidget {
  const _EventReplies({required this.e});
  final Map<String, dynamic> e;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final parts = [
      (s.t('coming'), e['coming'] as int, Brand.green),
      (s.t('maybe'), e['maybe'] as int, Brand.orange),
      (s.t('notComing'), e['declined'] as int, Brand.pink),
      (s.t('noReply'), e['pending'] as int, Brand.ink3),
    ];
    final meals = (e['meals_vegetarian'] as int) + (e['meals_vegan'] as int) + (e['meals_halal'] as int);
    return Panel(
      margin: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Eyebrow(fmtSl(e['starts_at'] as String)),
        const SizedBox(height: 6),
        Semantics(header: true, child: Text(e['name'] as String, style: Brand.display(26))),
        const SizedBox(height: 18),
        SplitBar(parts: [for (final p in parts) (p.$2, p.$3)], height: 12),
        const SizedBox(height: 16),
        for (var row = 0; row < 2; row++)
          Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : 14),
            child: Row(children: [
              for (final p in parts.skip(row * 2).take(2))
                Expanded(
                  child: Semantics(
                    label: '${p.$1}: ${p.$2}',
                    excludeSemantics: true,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      AnimatedCount(p.$2, style: Brand.display(28)),
                      const SizedBox(width: 10),
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: p.$3, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Flexible(child: Text(p.$1, style: const TextStyle(fontSize: 14, color: Brand.ink2, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                ),
            ]),
          ),
        const SizedBox(height: 18),
        const Divider(),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          AnimatedCount(e['headcount'] as int, style: Brand.display(44, color: Brand.success)),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${s.t('headcount')}${(e['maybe_headcount'] as int) > 0 ? '  ·  +${e['maybe_headcount']} ${s.t('maybe').toLowerCase()}' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ]),
        if (meals > 0) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if ((e['meals_vegetarian'] as int) > 0) StatusTag('${e['meals_vegetarian']} vegetarian', Brand.success),
            if ((e['meals_vegan'] as int) > 0) StatusTag('${e['meals_vegan']} vegan', Brand.success),
            if ((e['meals_halal'] as int) > 0) StatusTag('${e['meals_halal']} halal', Brand.warn),
          ]),
        ],
      ]),
    );
  }
}

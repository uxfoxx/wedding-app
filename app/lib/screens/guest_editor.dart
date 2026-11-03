import 'package:flutter/material.dart';

import '../ui.dart';

class GuestEditor extends StatefulWidget {
  const GuestEditor({super.key, this.guest, required this.onUpgrade});
  final Map<String, dynamic>? guest;
  final VoidCallback onUpgrade;
  @override
  State<GuestEditor> createState() => _GuestEditorState();
}

class _GuestEditorState extends State<GuestEditor> {
  late final g = widget.guest ?? {};
  late final name = TextEditingController(text: g['name'] ?? '');
  late final title = TextEditingController(text: g['title'] ?? '');
  late final phone = TextEditingController(text: g['phone'] ?? '');
  late final group = TextEditingController(text: g['group_name'] ?? '');
  late final dietary = TextEditingController(text: g['dietary'] ?? '');
  late final notes = TextEditingController(text: g['notes'] ?? '');
  late int seats = (g['seats'] as int?) ?? 1;
  late String? side = g['side'] as String?;
  late bool vip = g['vip'] == true;
  late Set<String> eventIds = {...((g['event_ids'] as List?)?.cast<String>() ?? const [])};
  bool busy = false;

  bool get isNew => widget.guest == null;

  @override
  void initState() {
    super.initState();
    if (isNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final evs = (AppScope.read(context).summary?['events'] as List?) ?? [];
        setState(() => eventIds = {for (final e in evs) e['id'] as String});
      });
    }
  }

  Future<void> save() async {
    final s = AppScope.read(context);
    final body = {
      'name': name.text.trim(), 'title': title.text.trim(), 'phone': phone.text.trim(), 'seats': seats,
      if (s.isAdvanced) ...{'side': side, 'group_name': group.text.trim(), 'vip': vip, 'dietary': dietary.text.trim(), 'notes': notes.text.trim(), 'event_ids': eventIds.toList()},
    };
    setState(() => busy = true);
    final r = await guard(
      context,
      () => isNew ? s.api.post('/weddings/${s.weddingId}/guests', body) : s.api.patch('/weddings/${s.weddingId}/guests/${g['id']}', body),
      onUpgrade: widget.onUpgrade,
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (r != null) {
      if (r['possibleDuplicateOf'] != null) toast(context, 'Note: ${r['possibleDuplicateOf']['name']} has the same number.');
      Navigator.pop(context, true);
    }
  }

  Future<void> remove() async {
    final s = AppScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text('Remove ${g['name']} from the guest list? Their invitation link will stop working.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('cancel'))), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('delete')))],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await guard(context, () => s.api.delete('/weddings/${s.weddingId}/guests/${g['id']}'));
    if (r != null && mounted) Navigator.pop(context, true);
  }

  /// A guest replied on WhatsApp instead of the page: paste their message and the app reads it.
  Future<void> recordReply() async {
    final s = AppScope.read(context);
    final text = TextEditingController();
    String status = 'coming';
    int headcount = (g['seats'] as int?) ?? 1;
    String? meal;
    String? summary;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Record their reply'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: text, maxLines: 3, decoration: const InputDecoration(labelText: 'Paste their message (optional)', hintText: 'api 3 denek enawa, elawalu')),
              TextButton.icon(
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Read message'),
                onPressed: () async {
                  final r = await s.api.post('/weddings/${s.weddingId}/read-reply', {'text': text.text}).catchError((_) => <String, dynamic>{});
                  set(() {
                    summary = r['summary'] as String?;
                    if (r['status'] != null) status = r['status'] as String;
                    if (r['headcount'] != null && (r['headcount'] as int) > 0) headcount = (r['headcount'] as int).clamp(1, (g['seats'] as int?) ?? 30);
                    meal = r['meal'] as String?;
                  });
                },
              ),
              if (summary != null) Text('Looks like: $summary. Check below.', style: const TextStyle(fontStyle: FontStyle.italic)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [ButtonSegment(value: 'coming', label: Text(s.t('coming'))), ButtonSegment(value: 'maybe', label: Text(s.t('maybe'))), ButtonSegment(value: 'not_coming', label: Text(s.t('notComing')))],
                selected: {status},
                onSelectionChanged: (v) => set(() => status = v.first),
              ),
              if (status != 'not_coming') ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Expanded(child: Text('People')),
                  IconButton(onPressed: headcount > 1 ? () => set(() => headcount--) : null, icon: const Icon(Icons.remove)),
                  Text('$headcount'),
                  IconButton(onPressed: headcount < ((g['seats'] as int?) ?? 30) ? () => set(() => headcount++) : null, icon: const Icon(Icons.add)),
                ]),
                DropdownButtonFormField<String?>(
                  initialValue: meal,
                  decoration: const InputDecoration(labelText: 'Meal'),
                  items: const [DropdownMenuItem(value: null, child: Text('No preference')), DropdownMenuItem(value: 'vegetarian', child: Text('Vegetarian')), DropdownMenuItem(value: 'vegan', child: Text('Vegan')), DropdownMenuItem(value: 'halal', child: Text('Halal'))],
                  onChanged: (v) => set(() => meal = v),
                ),
              ],
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('cancel'))), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('save')))],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final r = await guard(context, () => s.api.put('/weddings/${s.weddingId}/guests/${g['id']}/rsvp', {'status': status, 'headcount': headcount, 'meal': meal, 'note': text.text.trim().isEmpty ? null : text.text.trim()}));
    if (r != null && mounted) Navigator.pop(context, true);
  }

  Future<void> newLink() async {
    final s = AppScope.read(context);
    final r = await guard(context, () => s.api.post('/weddings/${s.weddingId}/guests/${g['id']}/new-link'));
    if (r != null && mounted) await copy(context, r['link'] as String, 'New link copied. The old link no longer works.');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final events = (s.summary?['events'] as List?) ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? s.t('addGuest') : g['name'] as String),
        actions: [
          if (!isNew && g['link'] != null) IconButton(tooltip: s.t('copyLink'), icon: const Icon(Icons.link), onPressed: () => copy(context, g['link'] as String, s.t('copied'))),
          if (!isNew)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'delete' ? remove() : v == 'reply' ? recordReply() : newLink(),
              itemBuilder: (_) => [const PopupMenuItem(value: 'reply', child: Text('Record their reply')), PopupMenuItem(value: 'link', child: Text(s.t('newLink'))), PopupMenuItem(value: 'delete', child: Text(s.t('delete')))],
            ),
        ],
      ),
      body: SafeArea(
        child: PageBody(maxWidth: 600, children: [
          TextField(key: const Key('guestName'), controller: name, autofocus: isNew, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: s.t('name'), hintText: 'Nimal & family')),
          const SizedBox(height: 12),
          TextField(controller: title, decoration: InputDecoration(labelText: s.t('title'))),
          const SizedBox(height: 12),
          TextField(key: const Key('guestPhone'), controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: s.t('phone'), hintText: '07X XXX XXXX or +44…')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text(s.t('seats'), style: Theme.of(context).textTheme.titleMedium)),
            IconButton.outlined(onPressed: seats > 1 ? () => setState(() => seats--) : null, icon: const Icon(Icons.remove)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Semantics(header: true, child: Text('$seats', style: Theme.of(context).textTheme.titleLarge))),
            IconButton.outlined(onPressed: seats < 30 ? () => setState(() => seats++) : null, icon: const Icon(Icons.add)),
          ]),
          if (s.isAdvanced) ...[
            const SizedBox(height: 12),
            SegmentedButton<String?>(
              emptySelectionAllowed: true,
              segments: [ButtonSegment(value: 'bride', label: Text(s.t('bride'))), ButtonSegment(value: 'groom', label: Text(s.t('groom'))), ButtonSegment(value: 'both', label: Text(s.t('both')))],
              selected: {if (side != null) side},
              onSelectionChanged: (v) => setState(() => side = v.isEmpty ? null : v.first),
            ),
            const SizedBox(height: 12),
            TextField(controller: group, decoration: InputDecoration(labelText: s.t('group'))),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(s.t('vip')), subtitle: const Text('VIPs who have not replied go to the top of the follow-up list'), value: vip, onChanged: (v) => setState(() => vip = v)),
            TextField(controller: dietary, decoration: InputDecoration(labelText: s.t('dietary'))),
            const SizedBox(height: 12),
            TextField(controller: notes, maxLines: 3, decoration: InputDecoration(labelText: s.t('notes'))),
            if (events.length > 1) ...[
              const SizedBox(height: 12),
              Text(s.t('events'), style: Theme.of(context).textTheme.titleMedium),
              for (final e in events)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: eventIds.contains(e['id']),
                  title: Text((e['title'] ?? e['kind']) as String),
                  subtitle: Text(fmtSl(e['starts_at'] as String)),
                  onChanged: (v) => setState(() => v == true ? eventIds.add(e['id'] as String) : eventIds.remove(e['id'])),
                ),
            ],
          ],
          const SizedBox(height: 20),
          FilledButton(key: const Key('saveGuest'), onPressed: busy ? null : save, child: Text(s.t('save'))),
        ]),
      ),
    );
  }
}

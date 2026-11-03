import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../ui.dart';

/// Import guests: paste text, an Excel/CSV file, or chosen phone contacts.
/// Step 1 reads the list on the server and flags unclear rows; step 2 saves what the couple confirms.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.format, required this.onUpgrade});
  final String format; // paste | csv | contacts
  final VoidCallback onUpgrade;

  static bool get contactsSupported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

const _flagText = {
  'phone_unreadable': 'Phone number unclear',
  'several_phones': 'More than one number',
  'no_name': 'No name',
  'digits_in_name': 'Name has numbers',
  'too_long': 'Very long name',
  'family_size_unknown': 'How many in the family?',
  'count_mismatch': 'Count looks wrong',
  'count_too_high': 'Too many people',
  'possible_duplicate': 'Already on the list?',
};

class _ImportScreenState extends State<ImportScreen> {
  final text = TextEditingController();
  List<Map<String, dynamic>>? rows;
  final Set<int> include = {};
  Map<String, dynamic>? meta;
  bool busy = false;

  // Contacts: the couple ticks who to import; nothing else leaves the phone.
  List<Contact>? contacts;
  final Set<int> pickedContacts = {};
  String contactQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.format == 'csv') WidgetsBinding.instance.addPostFrameCallback((_) => pickFile());
    if (widget.format == 'contacts') WidgetsBinding.instance.addPostFrameCallback((_) => loadContacts());
  }

  Future<void> pickFile() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt', 'tsv']);
    if (files.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final content = await files.first.xFile.readAsString();
    await read({'format': 'csv', 'text': content});
  }

  Future<void> loadContacts() async {
    final status = await FlutterContacts.permissions.request(PermissionType.read);
    if (status != PermissionStatus.granted && status != PermissionStatus.limited) {
      if (mounted) {
        toast(context, 'Allow access to contacts in Settings to import them.');
        Navigator.pop(context);
      }
      return;
    }
    final all = await FlutterContacts.getAll(properties: {ContactProperty.name, ContactProperty.phone});
    all.sort((a, b) => (a.displayName ?? '').compareTo(b.displayName ?? ''));
    if (mounted) setState(() => contacts = all.where((c) => (c.displayName ?? '').isNotEmpty).toList());
  }

  Future<void> read(Map<String, dynamic> body) async {
    final s = AppScope.read(context);
    setState(() => busy = true);
    final r = await guard(context, () => s.api.post('/weddings/${s.weddingId}/guests/import/preview', body));
    if (mounted) {
      setState(() {
        busy = false;
        if (r != null) {
          rows = (r['rows'] as List).cast<Map<String, dynamic>>();
          meta = r;
          include
            ..clear()
            ..addAll([for (var i = 0; i < rows!.length; i++) if (!(rows![i]['flags'] as List).contains('possible_duplicate')) i]);
        }
      });
    }
  }

  Future<void> save() async {
    final s = AppScope.read(context);
    final chosen = [for (final i in include.toList()..sort()) rows![i]];
    setState(() => busy = true);
    final r = await guard(
      context,
      () => s.api.post('/weddings/${s.weddingId}/guests/import', {
        'source': widget.format,
        'rows': [for (final g in chosen) {'name': g['name'], 'title': g['title'], 'phone': g['phone'], 'seats': g['seats'], 'dietary': g['dietary'], if (g['side'] != null) 'side': g['side'], if (g['group'] != null) 'group_name': g['group'], if (g['notes'] != null) 'notes': g['notes']}],
      }),
      onUpgrade: widget.onUpgrade,
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (r != null) {
      toast(context, 'Added ${r['added']} guests');
      Navigator.pop(context, true);
    }
  }

  Future<void> editRow(int i) async {
    final r = rows![i];
    final name = TextEditingController(text: r['name'] as String);
    final seats = TextEditingController(text: '${r['seats']}');
    final phone = TextEditingController(text: (r['phone'] ?? '') as String);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(r['raw'] as String? ?? ''),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 8),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
          const SizedBox(height: 8),
          TextField(controller: seats, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Seats')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('OK'))],
      ),
    );
    if (ok == true) {
      setState(() {
        rows![i] = {...r, 'name': name.text.trim(), 'phone': phone.text.trim().isEmpty ? null : phone.text.trim(), 'seats': int.tryParse(seats.text) ?? 1, 'flags': <String>[]};
        include.add(i);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    Widget body;

    if (rows != null) {
      final over = meta?['limit'] != null && (meta!['current'] as int) + include.length > (meta!['limit'] as int);
      body = PageBody(children: [
        Semantics(header: true, child: Text(s.t('checkRows'), style: th.textTheme.titleLarge)),
        const SizedBox(height: 4),
        const Text('Tap a guest to fix it. Rows marked with a warning need a look.'),
        if (over) Card(color: th.colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text('The free plan holds up to ${meta!['limit']} guests. You have ${meta!['current']}. Untick some guests or get the Wedding Pass.'))),
        const SizedBox(height: 8),
        for (var i = 0; i < rows!.length; i++)
          Card(
            child: CheckboxListTile(
              value: include.contains(i),
              onChanged: (v) => setState(() => v == true ? include.add(i) : include.remove(i)),
              title: Text([rows![i]['title'], rows![i]['name']].where((x) => x != null).join(' ')),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(['${rows![i]['seats']} seat(s)', if (rows![i]['phone'] != null) rows![i]['phone'], if (rows![i]['dietary'] != null) rows![i]['dietary']].join(' · ')),
                for (final f in (rows![i]['flags'] as List))
                  Row(children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: th.colorScheme.error),
                    const SizedBox(width: 4),
                    Flexible(child: Text('${_flagText[f] ?? f}${f == 'possible_duplicate' && rows![i]['duplicateOf'] != null ? ' (${rows![i]['duplicateOf']})' : ''}', style: TextStyle(color: th.colorScheme.error))),
                  ]),
              ]),
              secondary: IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Fix', onPressed: () => editRow(i)),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton(key: const Key('addRows'), onPressed: busy || include.isEmpty ? null : save, child: Text(s.t('addN', {'n': include.length}))),
      ]);
    } else if (widget.format == 'paste') {
      body = PageBody(children: [
        Semantics(header: true, child: Text(s.t('importPaste'), style: th.textTheme.titleLarge)),
        const SizedBox(height: 8),
        const Text('One guest per line, or separated by " / ". Counts ("2 people"), "& wife", "family", phone numbers and "veg" are understood.'),
        const SizedBox(height: 12),
        TextField(key: const Key('pasteBox'), controller: text, minLines: 8, maxLines: 20, decoration: InputDecoration(hintText: s.t('pasteHint'))),
        const SizedBox(height: 12),
        FilledButton(key: const Key('readList'), onPressed: busy ? null : () => read({'format': 'paste', 'text': text.text}), child: Text(s.t('read'))),
      ]);
    } else if (widget.format == 'contacts' && contacts != null) {
      final q = contactQuery.toLowerCase();
      final shown = [for (var i = 0; i < contacts!.length; i++) if (q.isEmpty || (contacts![i].displayName ?? '').toLowerCase().contains(q)) i];
      body = Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search contacts'), onChanged: (v) => setState(() => contactQuery = v)),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (_, k) {
              final c = contacts![shown[k]];
              return CheckboxListTile(
                value: pickedContacts.contains(shown[k]),
                onChanged: (v) => setState(() => v == true ? pickedContacts.add(shown[k]) : pickedContacts.remove(shown[k])),
                title: Text(c.displayName ?? ''),
                subtitle: Text(c.phones.isNotEmpty ? c.phones.first.number : 'No number'),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton(
              onPressed: pickedContacts.isEmpty || busy
                  ? null
                  : () => read({
                        'format': 'contacts',
                        'contacts': [for (final i in pickedContacts) {'name': contacts![i].displayName, 'phone': contacts![i].phones.isNotEmpty ? contacts![i].phones.first.number : null}],
                      }),
              child: Text('${s.t('next')} (${pickedContacts.length})'),
            ),
          ),
        ),
      ]);
    } else {
      body = const Center(child: CircularProgressIndicator());
    }

    return Scaffold(appBar: AppBar(title: Text(s.t('import'))), body: SafeArea(child: body));
  }
}

import 'package:flutter/material.dart';

import '../ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<dynamic>? members;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (members == null) load();
  }

  Future<void> load() async {
    final s = AppScope.read(context);
    final r = await s.api.get('/weddings/${s.weddingId}/members').catchError((_) => <String, dynamic>{'members': []});
    if (mounted) setState(() => members = r['members'] as List<dynamic>);
  }

  Future<void> inviteHelper() async {
    final s = AppScope.read(context);
    final role = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(title: Text(s.t('inviteHelper')), children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(c, 'edit_all'), child: const ListTile(title: Text('Can edit everything'))),
        SimpleDialogOption(onPressed: () => Navigator.pop(c, 'edit_guests'), child: const ListTile(title: Text('Can edit guests only'), subtitle: Text('Good for parents adding their friends'))),
        SimpleDialogOption(onPressed: () => Navigator.pop(c, 'view'), child: const ListTile(title: Text('Can view only'))),
      ]),
    );
    if (role == null || !mounted) return;
    final r = await guard(context, () => s.api.post('/weddings/${s.weddingId}/members/invite', {'role': role}));
    if (r == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.t('inviteHelper')),
        content: SelectableText(r['message'] as String),
        actions: [
          TextButton(onPressed: () => copy(c, r['message'] as String, s.t('copied')), child: Text(s.t('copyLink'))),
          FilledButton(onPressed: () => openUrl('https://wa.me/?text=${Uri.encodeComponent(r['message'] as String)}'), child: const Text('WhatsApp')),
        ],
      ),
    );
  }

  Future<void> deleteAccount() async {
    final s = AppScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.t('deleteAccount')),
        content: const Text('This deletes your account, and weddings you own together with their guest lists. Paid weddings are kept anonymously for our accounts. This cannot be undone.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('cancel'))), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('delete')))],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await guard(context, () => s.api.delete('/me', {'confirm': 'DELETE'}));
    if (r != null) {
      await s.signOut(callServer: false);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings'))),
      body: SafeArea(
        child: PageBody(children: [
          Text(s.t('mode'), style: th.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [ButtonSegment(value: 'easy', label: Text(s.t('easy'))), ButtonSegment(value: 'advanced', label: Text(s.t('advanced')))],
            selected: {s.wedding['mode'] as String? ?? 'easy'},
            onSelectionChanged: s.canEditAll ? (v) => guard(context, () async => s.setSummary(await s.api.patch('/weddings/${s.weddingId}', {'mode': v.first}))) : null,
          ),
          const Text('Switching never deletes anything.'),
          const SizedBox(height: 20),
          Text(s.t('language'), style: th.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'si', label: Text('සිංහල')), ButtonSegment(value: 'ta', label: Text('தமிழ்'))],
            selected: {s.locale},
            onSelectionChanged: (v) => s.setLocale(v.first),
          ),
          const SizedBox(height: 20),
          Text(s.t('coOwners'), style: th.textTheme.titleMedium),
          for (final m in members ?? [])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text((m['name'] ?? m['email'] ?? m['phone'] ?? '') as String),
              subtitle: Text({'owner': 'Owner', 'edit_all': 'Can edit everything', 'edit_guests': 'Can edit guests', 'view': 'Can view'}[m['role']] ?? ''),
              trailing: s.role == 'owner' && m['role'] != 'owner'
                  ? IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close),
                      onPressed: () async {
                        await guard(context, () => s.api.delete('/weddings/${s.weddingId}/members/${m['id']}'));
                        await load();
                      },
                    )
                  : null,
            ),
          if (s.role == 'owner') OutlinedButton.icon(onPressed: inviteHelper, icon: const Icon(Icons.group_add_outlined), label: Text(s.t('inviteHelper'))),
          const Divider(height: 40),
          ListTile(contentPadding: EdgeInsets.zero, title: Text(s.user?['email'] as String? ?? s.user?['phone'] as String? ?? '')),
          OutlinedButton(onPressed: () async {
            await s.signOut();
            if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
          }, child: Text(s.t('signOut'))),
          const SizedBox(height: 8),
          TextButton(onPressed: deleteAccount, style: TextButton.styleFrom(foregroundColor: th.colorScheme.error), child: Text(s.t('deleteAccount'))),
          const SizedBox(height: 8),
          Text('Guests\' phone numbers are deleted automatically 12 months after your wedding. Your album and messages stay as a keepsake.', style: th.textTheme.bodySmall),
        ]),
      ),
    );
  }
}

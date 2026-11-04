import 'package:flutter/cupertino.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings'))),
      body: SafeArea(bottom: false,
        child: PageBody(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
          SectionHeader(s.t('mode'), size: 24, padding: const EdgeInsets.fromLTRB(2, 8, 2, 10)),
          Segmented<String>(
            value: s.wedding['mode'] as String? ?? 'easy',
            options: [('easy', s.t('easy')), ('advanced', s.t('advanced'))],
            onChanged: s.canEditAll ? (v) => guard(context, () async => s.setSummary(await s.api.patch('/weddings/${s.weddingId}', {'mode': v}))) : null,
          ),
          const Padding(padding: EdgeInsets.fromLTRB(4, 8, 4, 0), child: Text('Switching never deletes anything.', style: TextStyle(color: Brand.ink2, fontSize: 14))),
          SectionHeader(s.t('language'), size: 24, padding: const EdgeInsets.fromLTRB(2, 24, 2, 10)),
          Segmented<String>(value: s.locale, options: const [('en', 'English'), ('si', 'සිංහල'), ('ta', 'தமிழ்')], onChanged: s.setLocale),
          SectionHeader(s.t('coOwners'), size: 24, padding: const EdgeInsets.fromLTRB(2, 24, 2, 10)),
          RowGroup(children: [
            for (final m in members ?? [])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Monogram((m['name'] ?? m['email'] ?? m['phone'] ?? '?') as String),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text((m['name'] ?? m['email'] ?? m['phone'] ?? '') as String, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text({'owner': 'Owner', 'edit_all': 'Can edit everything', 'edit_guests': 'Can edit guests', 'view': 'Can view'}[m['role']] ?? '', style: const TextStyle(color: Brand.ink2, fontSize: 13.5)),
                    ]),
                  ),
                  if (s.role == 'owner' && m['role'] != 'owner')
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(CupertinoIcons.minus_circle_fill, color: Color(0xFFFF3B30)),
                      onPressed: () async {
                        await guard(context, () => s.api.delete('/weddings/${s.weddingId}/members/${m['id']}'));
                        await load();
                      },
                    ),
                ]),
              ),
            if (s.role == 'owner') ActionRow(icon: CupertinoIcons.person_add_solid, tint: Brand.blue, title: s.t('inviteHelper'), onTap: inviteHelper),
          ]),
          const SizedBox(height: 18),
          RowGroup(children: [
            ActionRow(
              icon: CupertinoIcons.gift_fill,
              tint: Brand.orange,
              title: 'Invite friends',
              subtitle: 'They get a discount; you get credit towards your pass',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReferralScreen())),
            ),
            if (s.role == 'owner' && s.wedding['published_at'] != null)
              SwitchListTile.adaptive(
                title: const Text('Share our wedding in "Real weddings"'),
                subtitle: const Text('Your invitation design and the vendors you booked, shown to other couples after our team approves it.'),
                value: (s.wedding['showcase'] ?? 'off') != 'off',
                onChanged: (v) async {
                  await guard(context, () => s.api.post('/weddings/${s.weddingId}/showcase', {'share': v}));
                  await s.refresh();
                },
              ),
          ]),
          SectionHeader(s.t('account'), size: 24, padding: const EdgeInsets.fromLTRB(2, 24, 2, 10)),
          RowGroup(children: [
            ActionRow(
              icon: CupertinoIcons.square_arrow_right,
              tint: Brand.gray,
              title: s.t('signOut'),
              subtitle: s.user?['email'] as String? ?? s.user?['phone'] as String? ?? '',
              onTap: () async {
                await s.signOut();
                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
            ActionRow(icon: CupertinoIcons.trash_fill, tint: const Color(0xFFFF3B30), title: s.t('deleteAccount'), onTap: deleteAccount),
          ]),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('Guests\' phone numbers are deleted automatically 12 months after your wedding. Your album and messages stay as a keepsake.', style: TextStyle(color: Brand.ink2, fontSize: 13.5)),
          ),
        ]),
      ),
    );
  }
}

/// Account settings when no wedding is open (planner and vendor workspaces).
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings'))),
      body: PageBody(children: [
        Text(s.t('language'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Segmented<String>(value: s.locale, options: const [('en', 'English'), ('si', 'සිංහල'), ('ta', 'தமிழ்')], onChanged: s.setLocale),
        const Divider(height: 40),
        ListTile(contentPadding: EdgeInsets.zero, title: Text(s.user?['email'] as String? ?? s.user?['phone'] as String? ?? '')),
        OutlinedButton(
          onPressed: () async {
            await s.signOut();
            if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
          },
          child: Text(s.t('signOut')),
        ),
      ]),
    );
  }
}


class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});
  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  Map<String, dynamic>? r;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final v = await guard(context, () => AppScope.read(context).api.get('/me/referral'));
      if (v != null && mounted) setState(() => r = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Invite friends')),
      body: r == null
          ? const Center(child: CupertinoActivityIndicator())
          : PageBody(children: [
              Text('Friends get LKR ${r!['offer']['friend_discount_lkr']} off. You get LKR ${r!['offer']['your_credit_lkr']} credit when they buy the Wedding Pass.', style: th.textTheme.titleMedium),
              const SizedBox(height: 16),
              Card(child: ListTile(title: Text(r!['code'] as String, style: th.textTheme.headlineSmall?.copyWith(letterSpacing: 4)), subtitle: const Text('Your code'), trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () => copy(context, r!['code'] as String, 'Copied')))),
              const SizedBox(height: 8),
              FilledButton.icon(onPressed: () => openUrl('https://wa.me/?text=${Uri.encodeComponent(r!['message'] as String)}'), icon: const Icon(Icons.chat), label: const Text('Share on WhatsApp')),
              const SizedBox(height: 20),
              StatGrid(cols: isWide(context) ? 4 : 2, children: [
                StatTile('Friends joined', r!['referred']),
                StatTile('Bought the pass', r!['referred_paid']),
                StatTile('Your credit', 'LKR ${r!['credits_lkr']}'),
              ]),
            ]),
    );
  }
}

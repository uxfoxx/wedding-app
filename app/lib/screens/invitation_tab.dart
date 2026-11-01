import 'package:flutter/material.dart';

import '../ui.dart';

class InvitationTab extends StatefulWidget {
  const InvitationTab({super.key, required this.onGo});
  final void Function(String key) onGo;
  @override
  State<InvitationTab> createState() => _InvitationTabState();
}

class _InvitationTabState extends State<InvitationTab> {
  List<dynamic>? templates;
  final parents = TextEditingController();
  final message = TextEditingController();
  final cover = TextEditingController();
  final music = TextEditingController();
  String? loadedFor;
  bool busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    if (loadedFor != s.weddingId) {
      loadedFor = s.weddingId;
      final inv = (s.wedding['invitation'] as Map?) ?? {};
      parents.text = inv['parents'] ?? '';
      message.text = inv['message'] ?? '';
      cover.text = inv['cover_photo_url'] ?? '';
      music.text = inv['music_url'] ?? '';
    }
    if (templates == null) {
      s.api.get('/templates').then((r) {
        if (mounted) setState(() => templates = r['templates'] as List<dynamic>);
      }).catchError((_) {
        if (mounted) setState(() => templates = []);
      });
    }
  }

  Future<void> saveDetails() async {
    final s = AppScope.read(context);
    setState(() => busy = true);
    final r = await guard(context, () => s.api.patch('/weddings/${s.weddingId}', {
          'invitation': {'parents': parents.text, 'message': message.text, 'cover_photo_url': cover.text, 'music_url': music.text},
        }));
    if (r != null) {
      s.setSummary(r);
      if (mounted) toast(context, 'Saved');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> pickTemplate(Map t) async {
    final s = AppScope.read(context);
    if (t['premium'] == true && !s.isPaid) {
      // Anyone can look at a premium design; choosing it needs the pass.
      await preview(template: t['id'] as String);
      return;
    }
    final r = await guard(context, () => s.api.patch('/weddings/${s.weddingId}', {'template_id': t['id']}), onUpgrade: () => widget.onGo('upgrade'));
    if (r != null) s.setSummary(r);
  }

  Future<void> preview({String? template}) async {
    final s = AppScope.read(context);
    await saveDetails();
    if (!mounted) return;
    final r = await guard(context, () => s.api.post('/weddings/${s.weddingId}/preview-link', {'template': ?template}));
    if (r != null) await openUrl(r['url'] as String, inApp: true);
  }

  Future<void> publish() async {
    final s = AppScope.read(context);
    await saveDetails();
    if (!mounted) return;
    final r = await guard(context, () => s.api.post('/weddings/${s.weddingId}/publish'), onUpgrade: () => widget.onGo('upgrade'));
    if (r != null) {
      s.setSummary(r);
      if (mounted) toast(context, AppScope.read(context).t('published'));
    }
  }

  Future<void> chooseWording() async {
    final s = AppScope.read(context);
    final lang = s.wedding['language'] as String? ?? 'en';
    final r = await guard(context, () => s.api.get('/wordings', {'language': lang}));
    if (r == null || !mounted) return;
    final list = r['wordings'] as List<dynamic>;
    final picked = await showModalBottomSheet<Map>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
          Text(s.t('useWording'), style: Theme.of(c).textTheme.titleLarge),
          for (final w in list)
            Card(
              child: ListTile(
                title: Text(w['body'] as String),
                subtitle: Text('${w['tone']} · ${w['event_kind']}'),
                onTap: () => Navigator.pop(c, w as Map),
              ),
            ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    final f = await guard(context, () => s.api.post('/weddings/${s.weddingId}/wording/${picked['id']}/fill'));
    if (f != null) setState(() => message.text = f['text'] as String);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final w = s.wedding;
    final th = Theme.of(context);
    final published = w['published_at'] != null;
    final canEdit = s.canEditAll;

    return PageBody(maxWidth: 900, children: [
      if (published)
        Card(
          child: ListTile(
            leading: const Icon(Icons.public),
            title: Text(s.t('published')),
            subtitle: Text(w['page_url'] as String),
            trailing: FilledButton(key: const Key('sendFromInvitation'), onPressed: () => widget.onGo('send'), child: Text(s.t('sendInvites'))),
          ),
        ),
      Text(s.t('chooseDesign'), style: th.textTheme.titleLarge),
      const SizedBox(height: 8),
      if (templates == null)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: templates!.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _TemplateCard(
              t: templates![i] as Map<String, dynamic>,
              selected: w['template_id'] == templates![i]['id'],
              locked: templates![i]['premium'] == true && !s.isPaid,
              onTap: canEdit ? () => pickTemplate(templates![i] as Map) : null,
            ),
          ),
        ),
      const SizedBox(height: 20),
      Text(s.t('details'), style: th.textTheme.titleLarge),
      const SizedBox(height: 8),
      TextField(controller: parents, enabled: canEdit, decoration: InputDecoration(labelText: s.t('parents'))),
      const SizedBox(height: 12),
      TextField(controller: message, enabled: canEdit, minLines: 3, maxLines: 8, decoration: InputDecoration(labelText: s.t('message'))),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: canEdit ? chooseWording : null, icon: const Icon(Icons.auto_awesome_outlined), label: Text(s.t('useWording')))),
      if (s.isAdvanced) ...[
        TextField(controller: cover, enabled: canEdit, keyboardType: TextInputType.url, decoration: InputDecoration(labelText: s.t('coverPhoto'))),
        const SizedBox(height: 12),
        TextField(controller: music, enabled: canEdit, keyboardType: TextInputType.url, decoration: InputDecoration(labelText: s.t('music'))),
        const SizedBox(height: 12),
      ],
      DropdownButtonFormField<String>(
        initialValue: w['language'] as String? ?? 'en',
        decoration: InputDecoration(labelText: s.t('invitationLanguage')),
        items: const [DropdownMenuItem(value: 'en', child: Text('English')), DropdownMenuItem(value: 'si', child: Text('සිංහල')), DropdownMenuItem(value: 'ta', child: Text('தமிழ்'))],
        onChanged: canEdit ? (v) => guard(context, () async => s.setSummary(await s.api.patch('/weddings/${s.weddingId}', {'language': v}))) : null,
      ),
      const SizedBox(height: 20),
      Wrap(spacing: 12, runSpacing: 12, children: [
        OutlinedButton.icon(key: const Key('preview'), onPressed: busy ? null : () => preview(), icon: const Icon(Icons.visibility_outlined), label: Text(s.t('preview'))),
        if (canEdit) OutlinedButton(onPressed: busy ? null : saveDetails, child: Text(s.t('save'))),
        if (canEdit) FilledButton.icon(key: const Key('publish'), onPressed: busy ? null : publish, icon: const Icon(Icons.send_outlined), label: Text(s.t('publish'))),
      ]),
      if (published && canEdit) ...[
        const SizedBox(height: 24),
        SwitchListTile(
          title: Text(s.t('openLink')),
          subtitle: Text(w['open_link'] as String? ?? s.t('openLinkSub')),
          value: w['open_link'] != null,
          onChanged: (v) => guard(context, () async => s.setSummary(await s.api.post('/weddings/${s.weddingId}/open-link', {'enabled': v}))),
        ),
        if (w['open_link'] != null)
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(icon: const Icon(Icons.copy), label: Text(s.t('copyLink')), onPressed: () => copy(context, w['open_link'] as String, s.t('copied')))),
      ],
    ]);
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.t, required this.selected, required this.locked, this.onTap});
  final Map<String, dynamic> t;
  final bool selected, locked;
  final VoidCallback? onTap;

  Color _c(String hex) => Color(int.parse('FF${hex.substring(1)}', radix: 16));

  @override
  Widget build(BuildContext context) {
    final p = t['layout']['palette'] as Map<String, dynamic>;
    final th = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${t['name']}${locked ? ', Wedding Pass' : ''}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 140,
          decoration: BoxDecoration(
            color: _c(p['bg'] as String),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? th.colorScheme.primary : Colors.black12, width: selected ? 3 : 1),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (locked) Icon(Icons.lock_outline, size: 18, color: _c(p['accent'] as String)),
              const Spacer(),
              if (selected) Icon(Icons.check_circle, color: th.colorScheme.primary),
            ]),
            const Spacer(),
            Center(child: Text('A & B', style: TextStyle(fontSize: 26, fontFamily: 'serif', color: _c(p['accent'] as String), fontWeight: FontWeight.w700))),
            const Spacer(),
            Text(t['name'] as String, style: TextStyle(color: _c(p['ink'] as String), fontWeight: FontWeight.w600)),
            Text(t['category'] as String, style: TextStyle(color: _c(p['muted'] as String), fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

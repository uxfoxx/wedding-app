import 'package:flutter/material.dart';

import '../ui.dart';
import '../upload.dart';

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
          'invitation': {'parents': parents.text, 'message': message.text},
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

  // Only wording that fits this wedding (its faith and events), in its language; tone chips narrow it.
  Future<void> chooseWording() async {
    final s = AppScope.read(context);
    final r = await guard(context, () => s.api.get('/weddings/${s.weddingId}/wordings'));
    if (r == null || !mounted) return;
    final list = r['wordings'] as List<dynamic>;
    final tones = [for (final t in const ['formal', 'religious', 'modern', 'casual']) if (list.any((w) => w['tone'] == t)) t];
    String? tone;
    final picked = await showModalBottomSheet<Map>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) {
          final shown = [for (final w in list) if (tone == null || w['tone'] == tone) w];
          return SafeArea(
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
              Semantics(header: true, child: Text(s.t('useWording'), style: Theme.of(c).textTheme.titleLarge)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(label: Text(s.t('toneAll')), selected: tone == null, onSelected: (_) => setSheet(() => tone = null)),
                for (final t in tones) ChoiceChip(label: Text(s.t(t)), selected: tone == t, onSelected: (_) => setSheet(() => tone = t)),
              ]),
              const SizedBox(height: 8),
              if (shown.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text(s.t('noWording'), textAlign: TextAlign.center)),
              for (final w in shown)
                Card(
                  child: ListTile(
                    title: Text(w['body'] as String),
                    subtitle: Text('${s.t(w['tone'] as String)} · ${s.t(w['event_kind'] as String)}'),
                    onTap: () => Navigator.pop(c, w as Map),
                  ),
                ),
            ]),
          );
        },
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
      Semantics(header: true, child: Text(s.t('chooseDesign'), style: th.textTheme.titleLarge)),
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
      Semantics(header: true, child: Text(s.t('details'), style: th.textTheme.titleLarge)),
      const SizedBox(height: 8),
      TextField(controller: parents, enabled: canEdit, decoration: InputDecoration(labelText: s.t('parents'))),
      const SizedBox(height: 12),
      TextField(controller: message, enabled: canEdit, minLines: 3, maxLines: 8, decoration: InputDecoration(labelText: s.t('message'))),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: canEdit ? chooseWording : null, icon: const Icon(Icons.auto_awesome_outlined), label: Text(s.t('useWording')))),
      _InvitationMedia(canEdit: canEdit),
      const SizedBox(height: 12),
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

/// Cover photo for everyone; gallery and background music in Advanced Mode. Files upload straight
/// to storage and the server puts them on the invitation; removing one deletes the file.
class _InvitationMedia extends StatefulWidget {
  const _InvitationMedia({required this.canEdit});
  final bool canEdit;
  @override
  State<_InvitationMedia> createState() => _InvitationMediaState();
}

class _InvitationMediaState extends State<_InvitationMedia> {
  String? uploading;

  Future<void> upload(String kind) async {
    final s = AppScope.read(context);
    setState(() => uploading = kind);
    await guard(context, () => pickAndUpload(
          s.api,
          startPath: '/weddings/${s.weddingId}/invitation-media',
          completePath: (id) => '/weddings/${s.weddingId}/invitation-media/$id/complete',
          extra: {'kind': kind},
          audio: kind == 'music',
          single: kind != 'photo',
          onComplete: (r) => s.setSummary(r),
        ));
    if (mounted) setState(() => uploading = null);
  }

  Future<void> remove(Map<String, dynamic> change) async {
    final s = AppScope.read(context);
    final r = await guard(context, () => s.api.patch('/weddings/${s.weddingId}', {'invitation': change}));
    if (r != null) s.setSummary(r);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    final inv = (s.wedding['invitation'] as Map?) ?? {};
    final cover = inv['cover_photo_url'] as String?;
    final music = inv['music_url'] as String?;
    final photos = [for (final p in (inv['photos'] as List?) ?? const []) p as String];
    final can = widget.canEdit && uploading == null;
    Widget busy(String kind) => uploading == kind
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      Text(s.t('coverPhoto'), style: th.textTheme.titleMedium),
      const SizedBox(height: 8),
      Row(children: [
        if (cover != null && cover.isNotEmpty) ...[
          ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(cover, width: 96, height: 72, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 96, height: 72, child: Icon(Icons.broken_image_outlined)))),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(onPressed: can ? () => upload('cover') : null, icon: const Icon(Icons.photo_outlined), label: Text(s.t(cover == null || cover.isEmpty ? 'uploadPhoto' : 'change'))),
            if (cover != null && cover.isNotEmpty) TextButton(onPressed: can ? () => remove({'cover_photo_url': null}) : null, child: Text(s.t('remove'))),
            busy('cover'),
          ]),
        ),
      ]),
      if (s.isAdvanced) ...[
        const SizedBox(height: 16),
        Text('${s.t('gallery')} (${photos.length}/12)', style: th.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (photos.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in photos)
              Stack(children: [
                ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(p, width: 88, height: 88, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 88, height: 88, child: Icon(Icons.broken_image_outlined)))),
                if (widget.canEdit)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton.filledTonal(
                      tooltip: s.t('remove'),
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      onPressed: can ? () => remove({'photos': [for (final q in photos) if (q != p) q]}) : null,
                      icon: const Icon(Icons.close),
                    ),
                  ),
              ]),
          ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(onPressed: can && photos.length < 12 ? () => upload('photo') : null, icon: const Icon(Icons.add_photo_alternate_outlined), label: Text(s.t('addPhotos'))),
          busy('photo'),
        ]),
        const SizedBox(height: 16),
        Text(s.t('music'), style: th.textTheme.titleMedium),
        if (music != null && music.isNotEmpty)
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.music_note_outlined), title: Text(s.t('musicAdded')), subtitle: Text(Uri.parse(music).pathSegments.last)),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(onPressed: can ? () => upload('music') : null, icon: const Icon(Icons.upload_file_outlined), label: Text(s.t(music == null || music.isEmpty ? 'uploadMusic' : 'change'))),
          if (music != null && music.isNotEmpty) TextButton(onPressed: can ? () => remove({'music_url': null}) : null, child: Text(s.t('remove'))),
          busy('music'),
        ]),
      ],
    ]);
  }
}

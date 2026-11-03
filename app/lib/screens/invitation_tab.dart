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
    final published = w['published_at'] != null;
    final canEdit = s.canEditAll;
    final lang = w['language'] as String? ?? 'en';

    return PageBody(maxWidth: 900, padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
      if (published)
        Panel(
          color: Brand.ink,
          borderColor: Brand.ink,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const StatusTag('Live', Color(0xFF8FD3A8), filled: true),
              const Spacer(),
              IconButton(
                tooltip: s.t('copyLink'),
                color: Brand.paper,
                onPressed: () => copy(context, w['page_url'] as String, s.t('copied')),
                icon: const Icon(Icons.link_rounded),
              ),
            ]),
            const SizedBox(height: 10),
            Text(s.t('published'), style: Brand.display(28, color: Brand.paper)),
            const SizedBox(height: 4),
            Text(w['page_url'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Brand.paper.withValues(alpha: 0.6), fontSize: 13.5)),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('sendFromInvitation'),
              style: FilledButton.styleFrom(backgroundColor: Brand.paper, foregroundColor: Brand.ink),
              onPressed: () => widget.onGo('send'),
              icon: const Icon(Icons.send_rounded, size: 20),
              label: Text(s.t('sendInvites')),
            ),
          ]),
        ),
      SectionHeader(s.t('chooseDesign'), eyebrow: '01', padding: const EdgeInsets.fromLTRB(2, 18, 2, 14)),
      if (templates == null)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else
        SizedBox(
          height: 262,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: templates!.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _TemplateCard(
              t: templates![i] as Map<String, dynamic>,
              selected: w['template_id'] == templates![i]['id'],
              locked: templates![i]['premium'] == true && !s.isPaid,
              initials: ('${w['partner1']}'.characters.first, '${w['partner2']}'.characters.first),
              onTap: canEdit ? () => pickTemplate(templates![i] as Map) : null,
            ),
          ),
        ),
      SectionHeader(s.t('details'), eyebrow: '02'),
      TextField(controller: parents, enabled: canEdit, decoration: InputDecoration(labelText: s.t('parents'))),
      const SizedBox(height: 12),
      TextField(controller: message, enabled: canEdit, minLines: 4, maxLines: 10, decoration: InputDecoration(labelText: s.t('message'), alignLabelWithHint: true)),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(onPressed: canEdit ? chooseWording : null, icon: const Icon(Icons.auto_awesome_rounded, size: 18, color: Brand.accent), label: Text(s.t('useWording'))),
      ),
      const SizedBox(height: 18),
      Eyebrow(s.t('invitationLanguage')),
      const SizedBox(height: 10),
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'si', label: Text('සිංහල')), ButtonSegment(value: 'ta', label: Text('தமிழ்'))],
        selected: {lang},
        onSelectionChanged: canEdit ? (v) => guard(context, () async => s.setSummary(await s.api.patch('/weddings/${s.weddingId}', {'language': v.first}))) : null,
      ),
      SectionHeader(s.t(s.isAdvanced ? 'stepMedia' : 'coverPhoto'), eyebrow: '03'),
      _InvitationMedia(canEdit: canEdit),
      SectionHeader(s.t('stepShare'), eyebrow: '04'),
      Row(children: [
        Expanded(child: OutlinedButton.icon(key: const Key('preview'), onPressed: busy ? null : () => preview(), icon: const Icon(Icons.visibility_outlined, size: 20), label: Text(s.t('preview')))),
        if (canEdit) ...[
          const SizedBox(width: 10),
          OutlinedButton(onPressed: busy ? null : saveDetails, child: Text(s.t('save'))),
        ],
      ]),
      if (canEdit) ...[
        const SizedBox(height: 10),
        FilledButton.icon(key: const Key('publish'), onPressed: busy ? null : publish, icon: const Icon(Icons.send_rounded, size: 20), label: Text(s.t('publish'))),
      ],
      if (published && canEdit) ...[
        const SizedBox(height: 18),
        Panel(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Column(children: [
            SwitchListTile(
              title: Text(s.t('openLink')),
              subtitle: Text(w['open_link'] as String? ?? s.t('openLinkSub')),
              value: w['open_link'] != null,
              onChanged: (v) => guard(context, () async => s.setSummary(await s.api.post('/weddings/${s.weddingId}/open-link', {'enabled': v}))),
            ),
            if (w['open_link'] != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: TextButton.icon(icon: const Icon(Icons.copy_rounded, size: 18), label: Text(s.t('copyLink')), onPressed: () => copy(context, w['open_link'] as String, s.t('copied'))),
                ),
              ),
          ]),
        ),
      ],
    ]);
  }
}

/// A design shown as a tiny invitation: the template's own paper, ink and accent, a frame and
/// the couple's initials.
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.t, required this.selected, required this.locked, required this.initials, this.onTap});
  final Map<String, dynamic> t;
  final bool selected, locked;
  final (String, String) initials;
  final VoidCallback? onTap;

  Color _c(String hex) => Color(int.parse('FF${hex.substring(1)}', radix: 16));

  @override
  Widget build(BuildContext context) {
    final p = t['layout']['palette'] as Map<String, dynamic>;
    final accent = _c(p['accent'] as String);
    final ink = _c(p['ink'] as String);
    return Semantics(
      button: true,
      selected: selected,
      label: '${t['name']}${locked ? ', Wedding Pass' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 150,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 206,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? Brand.ink : Colors.transparent, width: 2),
              ),
              child: Container(
                decoration: BoxDecoration(color: _c(p['bg'] as String), borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.line)),
                padding: const EdgeInsets.all(9),
                child: Stack(children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: accent.withValues(alpha: 0.55))),
                    ),
                  ),
                  Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('TOGETHER WITH THEIR FAMILIES', textAlign: TextAlign.center, style: TextStyle(fontSize: 5.5, letterSpacing: 1, color: ink.withValues(alpha: 0.6), fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Text(initials.$1.toUpperCase(), style: Brand.display(34, color: ink)),
                      Text('&', style: Brand.display(22, color: accent, style: FontStyle.italic)),
                      Text(initials.$2.toUpperCase(), style: Brand.display(34, color: ink)),
                      const SizedBox(height: 10),
                      Flourish(color: accent, width: 52),
                    ]),
                  ),
                  if (locked)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(color: Brand.ink, shape: BoxShape.circle),
                        child: const Icon(Icons.lock_rounded, size: 12, color: Brand.paper),
                      ),
                    ),
                  if (selected)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Brand.ink, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded, size: 14, color: Brand.paper),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(t['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '${t['category']}${locked ? ' · Pass' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Brand.ink2, fontSize: 13),
              ),
            ),
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

    final hasCover = cover != null && cover.isNotEmpty;
    final hasMusic = music != null && music.isNotEmpty;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Cover: the photo itself, with its buttons on top; an upload tile when there is none.
      AspectRatio(
        aspectRatio: 16 / 10,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: hasCover
              ? Stack(fit: StackFit.expand, children: [
                  Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: Brand.sunk, child: const Icon(Icons.broken_image_outlined))),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Row(children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Brand.paper, foregroundColor: Brand.ink, minimumSize: const Size(0, 44)),
                        onPressed: can ? () => upload('cover') : null,
                        icon: uploading == 'cover' ? busy('cover') : const Icon(Icons.photo_outlined, size: 18),
                        label: Text(s.t('change')),
                      ),
                      const Spacer(),
                      IconButton.filled(
                        tooltip: s.t('remove'),
                        style: IconButton.styleFrom(backgroundColor: Brand.ink.withValues(alpha: 0.75), foregroundColor: Brand.paper),
                        onPressed: can ? () => remove({'cover_photo_url': null}) : null,
                        icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      ),
                    ]),
                  ),
                ])
              : _DropTile(
                  icon: Icons.add_photo_alternate_outlined,
                  label: s.t('uploadPhoto'),
                  busy: uploading == 'cover',
                  onTap: can ? () => upload('cover') : null,
                ),
        ),
      ),
      if (s.isAdvanced) ...[
        const SizedBox(height: 22),
        Row(children: [
          Expanded(child: Text(s.t('gallery'), style: th.textTheme.titleMedium)),
          Eyebrow('${photos.length} / 12'),
        ]),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: isWide(context) ? 6 : 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final p in photos)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(fit: StackFit.expand, children: [
                  Image.network(p, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: Brand.sunk, child: const Icon(Icons.broken_image_outlined))),
                  if (widget.canEdit)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: IconButton.filled(
                        tooltip: s.t('remove'),
                        iconSize: 16,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(backgroundColor: Brand.ink.withValues(alpha: 0.7), foregroundColor: Brand.paper),
                        onPressed: can ? () => remove({'photos': [for (final q in photos) if (q != p) q]}) : null,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                ]),
              ),
            if (photos.length < 12)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _DropTile(icon: Icons.add_rounded, label: s.t('addPhotos'), busy: uploading == 'photo', compact: true, onTap: can ? () => upload('photo') : null),
              ),
          ],
        ),
        const SizedBox(height: 22),
        RowGroup(children: [
          ActionRow(
            icon: hasMusic ? Icons.music_note_rounded : Icons.library_music_outlined,
            tint: hasMusic ? Brand.accent : null,
            title: hasMusic ? s.t('musicAdded') : s.t('music'),
            subtitle: hasMusic ? Uri.parse(music).pathSegments.last : s.t('uploadMusic'),
            onTap: can ? () => upload('music') : null,
            trailing: uploading == 'music'
                ? busy('music')
                : hasMusic
                    ? IconButton(tooltip: s.t('remove'), onPressed: can ? () => remove({'music_url': null}) : null, icon: const Icon(Icons.delete_outline_rounded, color: Brand.ink2))
                    : const Icon(Icons.upload_rounded, color: Brand.ink2),
          ),
        ]),
      ],
    ]);
  }
}

/// An empty slot to tap for an upload.
class _DropTile extends StatelessWidget {
  const _DropTile({required this.icon, required this.label, required this.busy, this.onTap, this.compact = false});
  final IconData icon;
  final String label;
  final bool busy, compact;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Brand.sunk,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: busy
                ? const CircularProgressIndicator()
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: compact ? 36 : 54,
                      height: compact ? 36 : 54,
                      decoration: BoxDecoration(color: Brand.surface, shape: BoxShape.circle, border: Border.all(color: Brand.line)),
                      child: Icon(icon, size: compact ? 20 : 26),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(label, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? 12.5 : 15)),
                    ),
                  ]),
          ),
        ),
      );
}

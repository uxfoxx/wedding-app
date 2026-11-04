import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

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
  PageController? carousel;
  int focused = 0;

  @override
  void dispose() {
    carousel?.dispose();
    super.dispose();
  }

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
    final list = templates;
    if (list != null && list.isNotEmpty && carousel == null) {
      focused = list.indexWhere((t) => t['id'] == w['template_id']).clamp(0, list.length - 1);
      carousel = PageController(viewportFraction: isWide(context) ? 0.28 : 0.52, initialPage: focused);
    }
    final current = list == null || list.isEmpty ? null : list[focused] as Map<String, dynamic>;

    return PageBody(title: s.t('invitation'), maxWidth: 900, padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
      if (published)
        Panel(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const IconTile(CupertinoIcons.globe, tint: Brand.green, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(s.t('published'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    const _LiveDot(),
                  ]),
                  Text(w['page_url'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Brand.ink2, fontSize: 14)),
                ]),
              ),
              IconButton(tooltip: s.t('copyLink'), onPressed: () => copy(context, w['page_url'] as String, s.t('copied')), icon: const Icon(CupertinoIcons.link)),
            ]),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('sendFromInvitation'),
              onPressed: () => widget.onGo('send'),
              icon: const Icon(CupertinoIcons.paperplane_fill, size: 19),
              label: Text(s.t('sendInvites')),
            ),
          ]),
        ),
      SectionHeader(s.t('chooseDesign'), padding: const EdgeInsets.fromLTRB(4, 18, 4, 4)),
      if (list == null)
        const Skeleton(height: 290)
      else if (list.isNotEmpty) ...[
        // Cover flow: the centred design faces you, its neighbours tilt away.
        SizedBox(
          height: 300,
          child: PageView.builder(
            controller: carousel,
            itemCount: list.length,
            clipBehavior: Clip.none,
            onPageChanged: (i) {
              HapticFeedback.selectionClick();
              setState(() => focused = i);
            },
            itemBuilder: (_, i) => AnimatedBuilder(
              animation: carousel!,
              builder: (_, child) {
                final page = carousel!.hasClients && carousel!.position.haveDimensions ? carousel!.page ?? focused.toDouble() : focused.toDouble();
                final d = (page - i).clamp(-1.5, 1.5);
                return Opacity(
                  opacity: (1 - 0.35 * d.abs()).clamp(0.3, 1),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateY(d * 0.55)
                      ..scaleByDouble(1 - 0.14 * d.abs(), 1 - 0.14 * d.abs(), 1, 1),
                    child: child,
                  ),
                );
              },
              child: _TemplateCard(
                t: list[i] as Map<String, dynamic>,
                selected: w['template_id'] == list[i]['id'],
                locked: list[i]['premium'] == true && !s.isPaid,
                initials: ('${w['partner1']}'.characters.first, '${w['partner2']}'.characters.first),
                onTap: () {
                  if (i != focused) {
                    carousel!.animateToPage(i, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
                  } else if (canEdit) {
                    pickTemplate(list[i] as Map);
                  }
                },
              ),
            ),
          ),
        ),
        if (current != null)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topCenter, children: [...prev, ?cur]),
            child: Column(key: ValueKey(current['id']), children: [
              Text(current['name'] as String, style: Brand.display(22)),
              const SizedBox(height: 2),
              Text(
                '${current['category']}'[0].toUpperCase() + '${current['category']}'.substring(1) + (current['premium'] == true ? ' · Wedding Pass' : ''),
                style: const TextStyle(color: Brand.ink2, fontSize: 15),
              ),
              const SizedBox(height: 12),
              if (w['template_id'] == current['id'])
                const StatusTag('In use', Brand.success, filled: true)
              else if (canEdit)
                current['premium'] == true && !s.isPaid
                    ? OutlinedButton.icon(onPressed: () => pickTemplate(current), icon: const Icon(CupertinoIcons.eye, size: 18), label: Text(s.t('preview')))
                    : FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => pickTemplate(current), child: Text(s.t('useDesign'))),
            ]),
          ),
      ],
      SectionHeader(s.t('details')),
      Panel(
        padding: EdgeInsets.zero,
        child: Column(children: [
          TextField(controller: parents, enabled: canEdit, decoration: InputDecoration(labelText: s.t('parents'), fillColor: Colors.transparent)),
          const Divider(indent: 16),
          TextField(controller: message, enabled: canEdit, minLines: 4, maxLines: 10, decoration: InputDecoration(labelText: s.t('message'), alignLabelWithHint: true, fillColor: Colors.transparent)),
        ]),
      ),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(onPressed: canEdit ? chooseWording : null, icon: const Icon(CupertinoIcons.sparkles, size: 18), label: Text(s.t('useWording'))),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 8), child: Eyebrow(s.t('invitationLanguage'))),
      Segmented<String>(
        value: lang,
        options: const [('en', 'English'), ('si', 'සිංහල'), ('ta', 'தமிழ்')],
        onChanged: canEdit ? (v) => guard(context, () async => s.setSummary(await s.api.patch('/weddings/${s.weddingId}', {'language': v}))) : null,
      ),
      SectionHeader(s.t(s.isAdvanced ? 'stepMedia' : 'coverPhoto')),
      _InvitationMedia(canEdit: canEdit),
      SectionHeader(s.t('stepShare')),
      Row(children: [
        Expanded(child: OutlinedButton.icon(key: const Key('preview'), onPressed: busy ? null : () => preview(), icon: const Icon(CupertinoIcons.eye, size: 19), label: Text(s.t('preview')))),
        if (canEdit) ...[
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: busy ? null : saveDetails, icon: const Icon(CupertinoIcons.tray_arrow_down, size: 19), label: Text(s.t('save')))),
        ],
      ]),
      if (canEdit) ...[
        const SizedBox(height: 10),
        FilledButton.icon(key: const Key('publish'), onPressed: busy ? null : publish, icon: const Icon(CupertinoIcons.paperplane_fill, size: 19), label: Text(s.t('publish'))),
      ],
      if (published && canEdit)
        RowGroup(header: s.t('openLink'), footer: w['open_link'] as String? ?? s.t('openLinkSub'), children: [
          ActionRow(
            icon: CupertinoIcons.person_3_fill,
            tint: Brand.teal,
            title: s.t('openLink'),
            trailing: Switch.adaptive(
              value: w['open_link'] != null,
              onChanged: (v) => guard(context, () async => s.setSummary(await s.api.post('/weddings/${s.weddingId}/open-link', {'enabled': v}))),
            ),
          ),
          if (w['open_link'] != null)
            ActionRow(icon: CupertinoIcons.link, tint: Brand.blue, title: s.t('copyLink'), onTap: () => copy(context, w['open_link'] as String, s.t('copied'))),
        ]),
    ]);
  }
}

/// A small pulsing green dot: the page is live.
class _LiveDot extends StatelessWidget {
  const _LiveDot();
  @override
  Widget build(BuildContext context) {
    final dot = Container(width: 8, height: 8, decoration: const BoxDecoration(color: Brand.green, shape: BoxShape.circle));
    if (Brand.reduceMotion(context)) return dot;
    return SizedBox(
      width: 18,
      height: 18,
      child: Stack(alignment: Alignment.center, children: [
        Container(width: 18, height: 18, decoration: BoxDecoration(color: Brand.green.withValues(alpha: 0.35), shape: BoxShape.circle))
            .animate(onPlay: (c) => c.repeat())
            .scaleXY(begin: 0.4, end: 1, duration: 1400.ms, curve: Curves.easeOut)
            .fadeOut(duration: 1400.ms, curve: Curves.easeIn),
        dot,
      ]),
    );
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: _c(p['bg'] as String),
              shape: Brand.squircle(22, side: BorderSide(color: selected ? Brand.accent : Colors.black.withValues(alpha: 0.06), width: selected ? 2.5 : 1)),
              shadows: [BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 24, offset: const Offset(0, 12))],
            ),
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Stack(children: [
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: accent.withValues(alpha: 0.55))))),
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('TOGETHER WITH THEIR FAMILIES', textAlign: TextAlign.center, style: TextStyle(fontSize: 6, letterSpacing: 1, color: ink.withValues(alpha: 0.6), fontWeight: FontWeight.w700)),
                    const SizedBox(height: 14),
                    Text(initials.$1.toUpperCase(), style: Brand.serifDisplay(46, color: ink)),
                    Text('&', style: Brand.serifDisplay(28, color: accent, style: FontStyle.italic)),
                    Text(initials.$2.toUpperCase(), style: Brand.serifDisplay(46, color: ink)),
                    const SizedBox(height: 14),
                    Flourish(color: accent, width: 60),
                  ]),
                ),
                if (locked || selected)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(color: selected ? Brand.accent : Colors.black.withValues(alpha: 0.75), shape: BoxShape.circle),
                      child: Icon(selected ? CupertinoIcons.checkmark_alt : CupertinoIcons.lock_fill, size: 12, color: Colors.white),
                    ),
                  ),
              ]),
            ),
          ),
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
                        style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.6), foregroundColor: Colors.white),
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
          padding: EdgeInsets.zero,
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
                        style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.6), foregroundColor: Colors.white),
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
                ? const CircularProgressIndicator.adaptive()
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

import 'package:flutter/material.dart';

import '../ui.dart';
import 'send_queue.dart';
import 'upgrade.dart';

/// Guest experience on the day: live updates, menu, guest photos (with approval), guestbook,
/// song requests, and the links/QR pages to show at the venue.
class ExperienceScreen extends StatefulWidget {
  const ExperienceScreen({super.key});
  @override
  State<ExperienceScreen> createState() => _ExperienceScreenState();
}

class _ExperienceScreenState extends State<ExperienceScreen> {
  Map<String, dynamic>? data;
  final update = TextEditingController();

  String get base => '/weddings/${AppScope.read(context).weddingId}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final r = await guard(context, () => AppScope.read(context).api.get('$base/experience'));
    if (r != null && mounted) setState(() => data = r);
  }

  Future<void> postUpdate() async {
    final s = AppScope.read(context);
    if (update.text.trim().isEmpty) return;
    final r = await guard(context, () => s.api.post('$base/updates', {'body': update.text.trim()}));
    if (r == null || !mounted) return;
    update.clear();
    await load();
    if (!mounted) return;
    final send = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Update posted'),
        content: const Text('Every guest sees it on their invitation page now. Also send it on WhatsApp to guests who said they are coming?'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send on WhatsApp'))],
      ),
    );
    if (send == true && mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SendQueueScreen(kind: 'update')));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    if (data == null) return Scaffold(appBar: AppBar(title: const Text('Guest experience')), body: const Center(child: CircularProgressIndicator()));
    final settings = data!['settings'] as Map<String, dynamic>;
    final counts = data!['counts'] as Map<String, dynamic>;
    final links = data!['links'] as Map<String, dynamic>;
    final published = s.wedding['published_at'] != null;
    void open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w)).then((_) => load());

    return Scaffold(
      appBar: AppBar(title: const Text('Guest experience')),
      body: RefreshIndicator(
        onRefresh: load,
        child: PageBody(maxWidth: 900, children: [
          if (!published) Card(color: th.colorScheme.tertiaryContainer, child: const ListTile(leading: Icon(Icons.info_outline), title: Text('Publish your invitation first'), subtitle: Text('These pages go live with your invitation.'))),
          Semantics(header: true, child: Text('Live updates', style: th.textTheme.titleLarge)),
          const Text('A change of time, venue, dress code or parking. Guests see it at the top of their invitation.'),
          const SizedBox(height: 8),
          if (s.canEditAll) ...[
            TextField(key: const Key('updateText'), controller: update, maxLines: 3, maxLength: 500, decoration: const InputDecoration(hintText: 'The reception now starts at 7:30 pm')),
            Align(alignment: Alignment.centerLeft, child: FilledButton.icon(key: const Key('postUpdate'), onPressed: postUpdate, icon: const Icon(Icons.campaign_outlined), label: const Text('Post update'))),
          ],
          for (final u in data!['updates'] as List)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.campaign_outlined),
              title: Text(u['body'] as String),
              subtitle: Text(fmtSl(u['created_at'] as String)),
              trailing: s.canEditAll
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove',
                      onPressed: () async {
                        await guard(context, () => s.api.delete('$base/updates/${u['id']}'));
                        await load();
                      },
                    )
                  : null,
            ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.restaurant_menu),
            title: const Text('Menu'),
            subtitle: Text((data!['menu'] as List).isEmpty ? 'Add dishes and allergens for guests to see' : '${(data!['menu'] as List).length} dishes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(MenuEditor(items: (data!['menu'] as List).cast<Map<String, dynamic>>())),
          ),
          const Divider(height: 32),
          Semantics(header: true, child: Text('Photos, guestbook and songs', style: th.textTheme.titleLarge)),
          if (!s.isPaid)
            Card(child: ListTile(leading: const Icon(Icons.lock_outline), title: const Text('Part of the Wedding Pass'), subtitle: const Text('Guests upload photos by QR code, leave voice notes and request songs.'), onTap: () => open(const UpgradeScreen())))
          else ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Guests can upload photos and messages'),
              value: settings['uploads_enabled'] == true,
              onChanged: s.canEditAll ? (v) => guard(context, () => s.api.patch('$base/experience/settings', {'uploads_enabled': v})).then((_) => load()) : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Check photos before they appear on the wall'),
              subtitle: const Text('Recommended: the wall is shown on a big screen at the reception.'),
              value: settings['wall_requires_approval'] == true,
              onChanged: s.canEditAll ? (v) => guard(context, () => s.api.patch('$base/experience/settings', {'wall_requires_approval': v})).then((_) => load()) : null,
            ),
            Card(child: ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text('Photos to check (${counts['pending']})'), subtitle: Text('${counts['approved']} on the wall · ${counts['storage_mb']} of ${counts['storage_limit_mb']} MB used'), trailing: const Icon(Icons.chevron_right), onTap: () => open(const PhotosScreen()))),
            Card(child: ListTile(leading: const Icon(Icons.menu_book_outlined), title: Text('Guestbook (${counts['guestbook']})'), trailing: const Icon(Icons.chevron_right), onTap: () => open(const GuestbookScreen()))),
            Card(child: ListTile(leading: const Icon(Icons.queue_music), title: Text('Song requests (${counts['songs']} waiting)'), trailing: const Icon(Icons.chevron_right), onTap: () => open(const SongsScreen()))),
          ],
          const Divider(height: 32),
          Semantics(header: true, child: Text('Pages for the venue', style: th.textTheme.titleLarge)),
          for (final l in [
            ('share', Icons.qr_code_2, 'Share photos & wishes', 'Print its QR code on table cards'),
            ('wall', Icons.tv, 'Live photo wall', 'Open on the screen or projector at the reception'),
            ('seat', Icons.event_seat_outlined, 'Find your seat', 'Shown once seating is published'),
            ('keepsake', Icons.auto_stories_outlined, 'Keepsake page', 'Album and guestbook after the wedding'),
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(l.$2),
              title: Text(l.$3),
              subtitle: Text(l.$4),
              trailing: Wrap(children: [
                IconButton(tooltip: 'Copy link', icon: const Icon(Icons.copy), onPressed: () => copy(context, links[l.$1] as String, 'Link copied')),
                IconButton(tooltip: 'Open', icon: const Icon(Icons.open_in_new), onPressed: () => openUrl(links[l.$1] as String)),
              ]),
            ),
          const Divider(height: 32),
          Semantics(header: true, child: Text('After the wedding', style: th.textTheme.titleLarge)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.favorite_outline),
            title: const Text('Send thank-you messages'),
            subtitle: const Text('To every guest who came, with a link to your photos and guestbook'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(const SendQueueScreen(kind: 'thanks')),
          ),
        ]),
      ),
    );
  }
}

class MenuEditor extends StatefulWidget {
  const MenuEditor({super.key, required this.items});
  final List<Map<String, dynamic>> items;
  @override
  State<MenuEditor> createState() => _MenuEditorState();
}

class _MenuEditorState extends State<MenuEditor> {
  late final items = [for (final i in widget.items) {...i}];

  Future<void> save() async {
    final s = AppScope.read(context);
    final r = await guard(context, () => s.api.put('/weddings/${s.weddingId}/menu', {'items': items.where((i) => '${i['name'] ?? ''}'.trim().isNotEmpty).toList()}));
    if (r != null && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Menu'), actions: [TextButton(onPressed: save, child: const Text('Save'))]),
      body: PageBody(children: [
        for (var i = 0; i < items.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Row(children: [
                  SizedBox(width: 120, child: TextFormField(initialValue: items[i]['course'] as String?, decoration: const InputDecoration(labelText: 'Course'), onChanged: (v) => items[i]['course'] = v)),
                  const SizedBox(width: 8),
                  Expanded(child: TextFormField(initialValue: items[i]['name'] as String?, decoration: const InputDecoration(labelText: 'Dish'), onChanged: (v) => items[i]['name'] = v)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => items.removeAt(i))),
                ]),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: ((items[i]['allergens'] as List?) ?? []).join(', '),
                  decoration: const InputDecoration(labelText: 'Allergens (comma separated)', hintText: 'cashew, milk, egg'),
                  onChanged: (v) => items[i]['allergens'] = v.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList(),
                ),
                Wrap(spacing: 8, children: [
                  for (final d in ['vegetarian', 'vegan', 'halal'])
                    FilterChip(
                      label: Text(d),
                      selected: ((items[i]['diet'] as List?) ?? []).contains(d),
                      onSelected: (on) => setState(() {
                        final l = [...((items[i]['diet'] as List?) ?? [])];
                        on ? l.add(d) : l.remove(d);
                        items[i]['diet'] = l;
                      }),
                    ),
                ]),
              ]),
            ),
          ),
        OutlinedButton.icon(onPressed: () => setState(() => items.add({'course': items.isEmpty ? 'Mains' : items.last['course'], 'name': '', 'allergens': [], 'diet': []})), icon: const Icon(Icons.add), label: const Text('Add dish')),
      ]),
    );
  }
}

class PhotosScreen extends StatefulWidget {
  const PhotosScreen({super.key});
  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  String status = 'pending';
  List<dynamic>? items;
  final selected = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final s = AppScope.read(context);
    final r = await guard(context, () => s.api.get('/weddings/${s.weddingId}/uploads', {'status': status}));
    if (r != null && mounted) setState(() { items = r['uploads'] as List<dynamic>; selected.clear(); });
  }

  Future<void> moderate(String to, Iterable<String> ids) async {
    final s = AppScope.read(context);
    await guard(context, () => s.api.post('/weddings/${s.weddingId}/uploads/moderate', {'ids': ids.toList(), 'status': to}));
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Guest photos')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'pending', label: Text('To check')), ButtonSegment(value: 'approved', label: Text('On the wall')), ButtonSegment(value: 'hidden', label: Text('Hidden'))],
            selected: {status},
            onSelectionChanged: (v) {
              setState(() { status = v.first; items = null; });
              load();
            },
          ),
        ),
        if (items != null && items!.isNotEmpty && s.canEditAll)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Text(selected.isEmpty ? 'Tap photos to select' : '${selected.length} selected'),
              const Spacer(),
              if (status != 'approved') FilledButton(onPressed: () => moderate('approved', selected.isEmpty ? items!.map((x) => x['id'] as String) : selected), child: Text(selected.isEmpty ? 'Approve all' : 'Approve')),
              const SizedBox(width: 8),
              if (status != 'hidden' && selected.isNotEmpty) OutlinedButton(onPressed: () => moderate('hidden', selected), child: const Text('Hide')),
            ]),
          ),
        Expanded(
          child: items == null
              ? const Center(child: CircularProgressIndicator())
              : items!.isEmpty
                  ? const Center(child: Text('Nothing here.'))
                  : GridView.extent(
                      maxCrossAxisExtent: 180,
                      padding: const EdgeInsets.all(12),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: [
                        for (final u in items!)
                          GestureDetector(
                            onTap: () => setState(() => selected.contains(u['id']) ? selected.remove(u['id']) : selected.add(u['id'] as String)),
                            child: Stack(fit: StackFit.expand, children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: u['kind'] == 'photo'
                                    ? Image.network(u['url'] as String, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12, child: Icon(Icons.broken_image)))
                                    : const ColoredBox(color: Colors.black26, child: Icon(Icons.play_circle_outline, size: 48)),
                              ),
                              if (u['reported'] == true) const Positioned(left: 6, top: 6, child: Chip(label: Text('Reported'), visualDensity: VisualDensity.compact)),
                              if (selected.contains(u['id'])) const Positioned(right: 6, top: 6, child: Icon(Icons.check_circle, color: Colors.white, size: 28)),
                              Positioned(left: 6, bottom: 6, child: Text(u['uploader'] as String? ?? '', style: const TextStyle(color: Colors.white, shadows: [Shadow(blurRadius: 4)]))),
                            ]),
                          ),
                      ],
                    ),
        ),
      ]),
    );
  }
}

class GuestbookScreen extends StatefulWidget {
  const GuestbookScreen({super.key});
  @override
  State<GuestbookScreen> createState() => _GuestbookScreenState();
}

class _GuestbookScreenState extends State<GuestbookScreen> {
  List<dynamic>? entries;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final s = AppScope.read(context);
    final r = await guard(context, () => s.api.get('/weddings/${s.weddingId}/guestbook'));
    if (r != null && mounted) setState(() => entries = r['entries'] as List<dynamic>);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Guestbook')),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
          : PageBody(children: [
              if (entries!.isEmpty) const Text('No messages yet. Share the "Share photos & wishes" link or QR code.'),
              for (final e in entries!)
                Card(
                  child: ListTile(
                    title: Text(e['name'] as String),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (e['message'] != null) Text(e['message'] as String),
                      if (e['voice_url'] != null) TextButton.icon(onPressed: () => openUrl(e['voice_url'] as String), icon: const Icon(Icons.play_arrow), label: const Text('Play voice note')),
                      if (e['status'] == 'hidden') const Text('Hidden from the keepsake page', style: TextStyle(fontStyle: FontStyle.italic)),
                    ]),
                    trailing: s.canEditAll
                        ? IconButton(
                            tooltip: e['status'] == 'hidden' ? 'Show' : 'Hide',
                            icon: Icon(e['status'] == 'hidden' ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () async {
                              await guard(context, () => s.api.patch('/weddings/${s.weddingId}/guestbook/${e['id']}', {'status': e['status'] == 'hidden' ? 'visible' : 'hidden'}));
                              await load();
                            },
                          )
                        : null,
                  ),
                ),
            ]),
    );
  }
}

class SongsScreen extends StatefulWidget {
  const SongsScreen({super.key});
  @override
  State<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends State<SongsScreen> {
  List<dynamic>? songs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final s = AppScope.read(context);
    final r = await guard(context, () => s.api.get('/weddings/${s.weddingId}/songs'));
    if (r != null && mounted) setState(() => songs = r['songs'] as List<dynamic>);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Song requests')),
      body: songs == null
          ? const Center(child: CircularProgressIndicator())
          : PageBody(children: [
              const Text('Share this screen with your DJ or band.'),
              for (final x in songs!)
                CheckboxListTile(
                  value: x['played_at'] != null,
                  title: Text(x['song'] as String),
                  subtitle: Text(x['name'] as String? ?? ''),
                  onChanged: (v) async {
                    await guard(context, () => s.api.patch('/weddings/${s.weddingId}/songs/${x['id']}', {'played': v}));
                    await load();
                  },
                ),
            ]),
    );
  }
}

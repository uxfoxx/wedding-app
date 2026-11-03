import 'package:flutter/material.dart';

import '../ui.dart';

/// Admin and designer staff: invitation templates and the wording library are data, so new
/// ones go live without an app update. Unpublished ones stay listed here but are hidden from couples.
class AdminTemplates extends StatefulWidget {
  const AdminTemplates({super.key});
  @override
  State<AdminTemplates> createState() => _AdminTemplatesState();
}

class _AdminTemplatesState extends State<AdminTemplates> {
  List<dynamic>? items;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final r = await guard(context, () => AppScope.read(context).api.get('/admin/templates'));
    if (r != null && mounted) setState(() => items = r['templates'] as List<dynamic>);
  }

  Future<void> edit(Map<String, dynamic>? t) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _TemplateEditor(t: t)));
    if (saved == true) await load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Templates')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => edit(null), icon: const Icon(Icons.add), label: const Text('New template')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : PageBody(maxWidth: 900, children: [
              Text('${items!.where((t) => t['published'] == true).length} published · ${items!.where((t) => t['premium'] != true && t['published'] == true).length} free'),
              const SizedBox(height: 8),
              for (final t in items!)
                Card(
                  child: ListTile(
                    leading: _Swatch(palette: (t['layout']['palette'] as Map).cast<String, dynamic>()),
                    title: Text('${t['name']}${t['published'] == true ? '' : ' (hidden)'}'),
                    subtitle: Text([t['category'], t['premium'] == true ? 'Wedding Pass' : 'Free', t['layout']['animation'], if (t['partner_code'] != null) 'partner ${t['partner_code']}'].join(' · ')),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => edit((t as Map).cast<String, dynamic>()),
                  ),
                ),
              const SizedBox(height: 72),
            ]),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette});
  final Map<String, dynamic> palette;
  @override
  Widget build(BuildContext context) {
    Color c(String k) => hexColor(palette[k] as String?) ?? Colors.grey;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: c('bg'), borderRadius: BorderRadius.circular(8), border: Border.all(color: c('muted'))),
      alignment: Alignment.center,
      child: Container(width: 16, height: 16, decoration: BoxDecoration(color: c('accent'), shape: BoxShape.circle)),
    );
  }
}

Color? hexColor(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(int.parse('ff${hex.substring(1)}', radix: 16));
}

class _TemplateEditor extends StatefulWidget {
  const _TemplateEditor({this.t});
  final Map<String, dynamic>? t;
  @override
  State<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<_TemplateEditor> {
  static const paletteKeys = {'bg': 'Background', 'surface': 'Card', 'ink': 'Text', 'accent': 'Accent', 'muted': 'Secondary text'};
  late final id = TextEditingController(text: widget.t?['id'] as String? ?? '');
  late final name = TextEditingController(text: widget.t?['name'] as String? ?? '');
  late final category = TextEditingController(text: widget.t?['category'] as String? ?? 'modern');
  late final sort = TextEditingController(text: '${widget.t?['sort'] ?? 100}');
  late final Map<String, TextEditingController> palette = {
    for (final k in paletteKeys.keys) k: TextEditingController(text: (widget.t?['layout']?['palette']?[k] as String?) ?? (k == 'bg' ? '#fbf6ec' : k == 'ink' ? '#2b1d12' : k == 'accent' ? '#a8742a' : k == 'muted' ? '#6e5a48' : '#ffffff')),
  };
  late bool premium = widget.t?['premium'] == true;
  late bool published = widget.t?['published'] != false;
  late String font = widget.t?['layout']?['headingFont'] as String? ?? 'serif';
  late String ornament = widget.t?['layout']?['ornament'] as String? ?? 'none';
  late String animation = widget.t?['layout']?['animation'] as String? ?? 'none';
  late String hero = widget.t?['layout']?['hero'] as String? ?? 'monogram';

  Future<void> save() async {
    final s = AppScope.read(context);
    final ok = await guard(context, () => s.api.put('/admin/templates/${id.text.trim()}', {
          'name': name.text.trim(),
          'category': category.text.trim(),
          'premium': premium,
          'published': published,
          'sort': int.tryParse(sort.text) ?? 100,
          'layout': {
            'palette': {for (final e in palette.entries) e.key: e.value.text.trim()},
            'headingFont': font,
            'ornament': ornament,
            'animation': animation,
            'hero': hero,
          },
        }));
    if (ok != null && mounted) Navigator.pop(context, true);
  }

  Widget pick(String label, String value, List<String> options, void Function(String) set) => DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o))],
        onChanged: (v) => setState(() => set(v!)),
      );

  @override
  Widget build(BuildContext context) {
    final isNew = widget.t == null;
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'New template' : 'Edit ${widget.t!['name']}')),
      body: PageBody(children: [
        TextField(controller: id, enabled: isNew, decoration: const InputDecoration(labelText: 'Id (lowercase-with-dashes, cannot change later)')),
        const SizedBox(height: 12),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 12),
        TextField(controller: category, decoration: const InputDecoration(labelText: 'Category (traditional, church, nikah, kovil, modern, minimal, homecoming)')),
        const SizedBox(height: 12),
        TextField(controller: sort, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Order in the list')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Wedding Pass only'), value: premium, onChanged: (v) => setState(() => premium = v)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Published'), subtitle: const Text('Hidden templates stay on weddings already using them'), value: published, onChanged: (v) => setState(() => published = v)),
        const SizedBox(height: 8),
        Text('Colours', style: Theme.of(context).textTheme.titleMedium),
        for (final e in paletteKeys.entries)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ValueListenableBuilder(
              valueListenable: palette[e.key]!,
              builder: (_, v, _) => TextField(
                controller: palette[e.key],
                decoration: InputDecoration(
                  labelText: '${e.value} (#rrggbb)',
                  prefixIcon: Padding(padding: const EdgeInsets.all(12), child: CircleAvatar(radius: 10, backgroundColor: hexColor(v.text.trim()) ?? Colors.transparent)),
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        pick('Heading font', font, const ['serif', 'sans', 'script'], (v) => font = v),
        const SizedBox(height: 12),
        pick('Ornament', ornament, const ['none', 'lotus', 'kolam', 'floral', 'geometric', 'cross', 'arch', 'lines'], (v) => ornament = v),
        const SizedBox(height: 12),
        pick('Opening animation', animation, const ['none', 'envelope', 'curtain', 'scroll'], (v) => animation = v),
        const SizedBox(height: 12),
        pick('Top of the page', hero, const ['photo', 'monogram', 'pattern'], (v) => hero = v),
        const SizedBox(height: 20),
        FilledButton(onPressed: save, child: const Text('Save')),
      ]),
    );
  }
}

class AdminWordings extends StatefulWidget {
  const AdminWordings({super.key});
  @override
  State<AdminWordings> createState() => _AdminWordingsState();
}

class _AdminWordingsState extends State<AdminWordings> {
  List<dynamic>? items;
  String language = 'en';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final r = await guard(context, () => AppScope.read(context).api.get('/admin/wordings'));
    if (r != null && mounted) setState(() => items = r['wordings'] as List<dynamic>);
  }

  Future<void> edit(Map<String, dynamic>? w) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _WordingEditor(w: w, language: language)));
    if (saved == true) await load();
  }

  @override
  Widget build(BuildContext context) {
    final shown = [for (final w in items ?? const []) if (w['language'] == language) w];
    return Scaffold(
      appBar: AppBar(title: const Text('Wording library')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => edit(null), icon: const Icon(Icons.add), label: const Text('New wording')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : PageBody(maxWidth: 900, children: [
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'si', label: Text('සිංහල')), ButtonSegment(value: 'ta', label: Text('தமிழ்'))],
                selected: {language},
                onSelectionChanged: (v) => setState(() => language = v.first),
              ),
              const SizedBox(height: 8),
              const Text('Fields filled in for the couple: {couple}, {date}, {venue}, {parents}. Faith decides which weddings see it; "any" suits every wedding.'),
              const SizedBox(height: 8),
              for (final w in shown)
                Card(
                  child: ListTile(
                    title: Text(w['body'] as String),
                    subtitle: Text('${w['event_kind']} · ${w['tone']} · ${w['faith'] ?? 'any faith'}${w['published'] == true ? '' : ' · hidden'}'),
                    onTap: () => edit((w as Map).cast<String, dynamic>()),
                  ),
                ),
              const SizedBox(height: 72),
            ]),
    );
  }
}

class _WordingEditor extends StatefulWidget {
  const _WordingEditor({this.w, required this.language});
  final Map<String, dynamic>? w;
  final String language;
  @override
  State<_WordingEditor> createState() => _WordingEditorState();
}

class _WordingEditorState extends State<_WordingEditor> {
  late final body = TextEditingController(text: widget.w?['body'] as String? ?? '');
  late String language = widget.w?['language'] as String? ?? widget.language;
  late String tone = widget.w?['tone'] as String? ?? 'formal';
  late String eventKind = widget.w?['event_kind'] as String? ?? 'wedding';
  late String faith = widget.w?['faith'] as String? ?? '';
  late bool published = widget.w?['published'] != false;

  Future<void> save() async {
    final s = AppScope.read(context);
    final data = {'tone': tone, 'event_kind': eventKind, 'faith': faith, 'body': body.text.trim()};
    final ok = await guard(context, () => widget.w == null
        ? s.api.post('/admin/wordings', {...data, 'language': language})
        : s.api.patch('/admin/wordings/${widget.w!['id']}', {...data, 'published': published}));
    if (ok != null && mounted) Navigator.pop(context, true);
  }

  Widget pick(String label, String value, Map<String, String> options, void Function(String) set, {bool enabled = true}) => DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [for (final o in options.entries) DropdownMenuItem(value: o.key, child: Text(o.value))],
        onChanged: enabled ? (v) => setState(() => set(v!)) : null,
      );

  @override
  Widget build(BuildContext context) {
    final isNew = widget.w == null;
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'New wording' : 'Edit wording')),
      body: PageBody(children: [
        pick('Language', language, const {'en': 'English', 'si': 'සිංහල', 'ta': 'தமிழ்'}, (v) => language = v, enabled: isNew),
        const SizedBox(height: 12),
        pick('Occasion', eventKind, const {'wedding': 'Wedding', 'homecoming': 'Homecoming', 'engagement': 'Engagement'}, (v) => eventKind = v),
        const SizedBox(height: 12),
        pick('Tone', tone, const {'formal': 'Formal', 'religious': 'Religious', 'modern': 'Modern', 'casual': 'Casual'}, (v) => tone = v),
        const SizedBox(height: 12),
        pick('Faith', faith, const {'': 'Any wedding', 'buddhist': 'Buddhist', 'hindu': 'Hindu', 'muslim': 'Muslim', 'christian': 'Christian'}, (v) => faith = v),
        const SizedBox(height: 12),
        TextField(controller: body, minLines: 4, maxLines: 10, decoration: const InputDecoration(labelText: 'Wording', hintText: '{parents} invite you to the wedding of {couple} on {date} at {venue}.')),
        if (!isNew) SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Published'), value: published, onChanged: (v) => setState(() => published = v)),
        const SizedBox(height: 20),
        FilledButton(onPressed: save, child: const Text('Save')),
      ]),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ui.dart';
import '../upload.dart';
import 'budget.dart' show lkr;
import 'planner_home.dart' show WorkspaceMenu;
import 'settings.dart';
import 'vendor_setup.dart';

/// Vendor workspace: enquiries, profile & portfolio, packages, availability, stats and reviews.
class VendorHome extends StatefulWidget {
  const VendorHome({super.key});
  @override
  State<VendorHome> createState() => _VendorHomeState();
}

class _VendorHomeState extends State<VendorHome> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final v = s.vendor?['vendor'] as Map<String, dynamic>? ?? {};
    final tabs = <(String, IconData, Widget)>[
      ('Enquiries', Icons.inbox_outlined, const _Enquiries()),
      ('Profile', Icons.storefront_outlined, const _Profile()),
      ('Calendar', Icons.calendar_month_outlined, const _Availability()),
      ('Stats', Icons.insights_outlined, const _Stats()),
    ];
    final wide = isWide(context);
    final body = IndexedStack(index: index, children: [for (final t in tabs) t.$3]);
    return Scaffold(
      appBar: AppBar(
        title: Text(v['business_name'] as String? ?? 'My business'),
        actions: [
          const WorkspaceMenu(),
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: s.t('settings'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountScreen()))),
        ],
      ),
      body: Column(children: [
        if (v['status'] != 'approved') _StatusBanner(status: v['status'] as String? ?? 'draft'),
        Expanded(
          child: wide
              ? Row(children: [
                  NavigationRail(selectedIndex: index, labelType: NavigationRailLabelType.all, onDestinationSelected: (i) => setState(() => index = i),
                      destinations: [for (final t in tabs) NavigationRailDestination(icon: Icon(t.$2), label: Text(t.$1))]),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ])
              : body,
        ),
      ]),
      bottomNavigationBar: wide ? null : NavigationBar(selectedIndex: index, onDestinationSelected: (i) => setState(() => index = i), destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.$2), label: t.$1)]),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final (text, color) = switch (status) {
      'pending' => ('We are checking your business: phone, registration and original portfolio. You go live once approved.', th.colorScheme.tertiaryContainer),
      'under_review' => ('Your profile is hidden while our team looks into complaints. We will contact you.', th.colorScheme.errorContainer),
      'suspended' => ('Your profile is suspended. Please contact support.', th.colorScheme.errorContainer),
      _ => ('Add at least 3 photos of your real work and one package, then submit for review.', th.colorScheme.secondaryContainer),
    };
    return MaterialBanner(
      backgroundColor: color,
      content: Text(text),
      actions: [
        if (status == 'draft')
          TextButton(
            onPressed: () async {
              final s = AppScope.read(context);
              final r = await guard(context, () => s.api.post('/vendor/submit'));
              if (r != null) {
                await s.loadVendor();
                s.touch();
                if (context.mounted) toast(context, 'Submitted. We will review it soon.');
              }
            },
            child: const Text('Submit for review'),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }
}

class _Enquiries extends StatefulWidget {
  const _Enquiries();
  @override
  State<_Enquiries> createState() => _EnquiriesState();
}

class _EnquiriesState extends State<_Enquiries> {
  List<dynamic>? list;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final r = await guard(context, () => AppScope.read(context).api.get('/vendor/enquiries'));
    if (r != null && mounted) setState(() => list = r['enquiries'] as List<dynamic>);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    if (list == null) return const Center(child: CircularProgressIndicator());
    if (list!.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No enquiries yet. Couples will contact you here with their wedding date, venue and guest count.', textAlign: TextAlign.center)));
    return RefreshIndicator(
      onRefresh: load,
      child: PageBody(maxWidth: 900, children: [
        for (final e in list!)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(e['vendor_status'] == 'new' ? Icons.mark_email_unread_outlined : Icons.mail_outline)),
              title: Text('${e['partner1']} & ${e['partner2']}', style: TextStyle(fontWeight: e['vendor_status'] == 'new' ? FontWeight.w700 : null)),
              subtitle: Text([
                if (e['wedding_date'] != null) fmtSl(e['wedding_date'] as String),
                if (e['guest_count'] != null) '${e['guest_count']} guests',
                if (e['location'] != null) e['location'],
                e['last_message'] ?? '',
              ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Chip(label: Text(e['vendor_status'] as String), backgroundColor: e['vendor_status'] == 'new' ? th.colorScheme.primaryContainer : null),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VendorEnquiryScreen(id: e['id'] as String))).then((_) => load()),
            ),
          ),
      ]),
    );
  }
}

class VendorEnquiryScreen extends StatefulWidget {
  const VendorEnquiryScreen({super.key, required this.id});
  final String id;
  @override
  State<VendorEnquiryScreen> createState() => _VendorEnquiryScreenState();
}

class _VendorEnquiryScreenState extends State<VendorEnquiryScreen> {
  Map<String, dynamic>? data;
  final reply = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final r = await guard(context, () => AppScope.read(context).api.get('/vendor/enquiries/${widget.id}'));
    if (r != null && mounted) setState(() => data = r);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    if (data == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final e = data!['enquiry'] as Map<String, dynamic>;
    return Scaffold(
      appBar: AppBar(title: Text('${e['partner1']} & ${e['partner2']}')),
      body: PageBody(children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Wedding details', style: th.textTheme.titleMedium),
              if (e['wedding_date'] != null) Text('Date: ${fmtSl(e['wedding_date'] as String)}'),
              if (e['location'] != null) Text('Where: ${e['location']}'),
              if (e['guest_count'] != null) Text('Guests: ${e['guest_count']}'),
              Text(e['budget_lkr'] != null ? 'Budget: ${lkr(num.parse('${e['budget_lkr']}'))}' : 'Budget: not shared'),
              Text('Contact: ${e['contact_name'] ?? ''} ${e['contact_phone'] ?? e['contact_email'] ?? ''}'),
            ]),
          ),
        ),
        Wrap(spacing: 8, children: [
          for (final st in const ['quoted', 'booked', 'declined'])
            ChoiceChip(
              label: Text(st),
              selected: e['vendor_status'] == st,
              onSelected: (_) async {
                await guard(context, () => s.api.patch('/vendor/enquiries/${widget.id}', {'status': st}));
                await load();
              },
            ),
        ]),
        const SizedBox(height: 12),
        for (final m in data!['messages'] as List)
          Align(
            alignment: m['from_side'] == 'vendor' ? Alignment.centerRight : Alignment.centerLeft,
            child: Card(
              color: m['from_side'] == 'vendor' ? th.colorScheme.primaryContainer : null,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(m['body'] as String)),
            ),
          ),
        const SizedBox(height: 8),
        TextField(controller: reply, maxLines: 4, decoration: const InputDecoration(hintText: 'Write a reply…')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(
            onPressed: () async {
              if (reply.text.trim().isEmpty) return;
              await guard(context, () => s.api.post('/vendor/enquiries/${widget.id}/reply', {'body': reply.text.trim()}));
              reply.clear();
              await load();
            },
            child: const Text('Send reply'),
          ),
          if (data!['whatsapp'] != null) OutlinedButton.icon(onPressed: () => openUrl(data!['whatsapp'] as String), icon: const Icon(Icons.chat), label: const Text('WhatsApp')),
          OutlinedButton(
            onPressed: () async {
              final r = await guard(context, () => s.api.post('/vendor/enquiries/${widget.id}/request-review'));
              if (r != null) await openUrl(r['whatsapp'] as String);
            },
            child: const Text('Ask for a review'),
          ),
        ]),
      ]),
    );
  }
}

class _Profile extends StatefulWidget {
  const _Profile();
  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  bool uploading = false;

  Future<void> reload() async {
    final s = AppScope.read(context);
    await s.loadVendor();
    s.touch();
    if (mounted) setState(() {});
  }

  Future<void> upload() async {
    final s = AppScope.read(context);
    setState(() => uploading = true);
    final n = await guard(context, () => pickAndUpload(s.api, startPath: '/vendor/media', completePath: (id) => '/vendor/media/$id/complete', videos: true));
    if (mounted) setState(() => uploading = false);
    if (n != null && n > 0) {
      await reload();
      if (mounted) toast(context, 'Added $n');
    }
  }

  Future<void> editPackage([Map<String, dynamic>? p]) async {
    final s = AppScope.read(context);
    final name = TextEditingController(text: p?['name'] ?? '');
    final includes = TextEditingController(text: p?['includes'] ?? '');
    final price = TextEditingController(text: p != null ? '${p['starting_lkr']}' : '');
    bool negotiable = p?['negotiable'] != false;
    final r = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(p == null ? 'Add package' : 'Package'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name', hintText: 'Full-day coverage')),
              const SizedBox(height: 8),
              TextField(controller: includes, maxLines: 3, decoration: const InputDecoration(labelText: "What's included")),
              const SizedBox(height: 8),
              TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Starting price (LKR)')),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Price is negotiable'), value: negotiable, onChanged: (v) => set(() => negotiable = v)),
            ]),
          ),
          actions: [
            if (p != null) TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Delete')),
            FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (!mounted || r == null) return;
    if (r == 'delete') {
      await guard(context, () => s.api.delete('/vendor/packages/${p!['id']}'));
    } else {
      final body = {'name': name.text.trim(), 'includes': includes.text.trim(), 'starting_lkr': num.tryParse(price.text.replaceAll(',', '')) ?? 0, 'negotiable': negotiable};
      await guard(context, () => p == null ? s.api.post('/vendor/packages', body) : s.api.patch('/vendor/packages/${p['id']}', body));
    }
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    final data = s.vendor ?? {};
    final v = data['vendor'] as Map<String, dynamic>? ?? {};
    final media = (data['media'] as List?) ?? [];
    final packages = (data['packages'] as List?) ?? [];
    return RefreshIndicator(
      onRefresh: reload,
      child: PageBody(maxWidth: 1000, children: [
        Row(children: [
          Expanded(child: Semantics(header: true, child: Text('${v['business_name']} · ${v['district']}', style: th.textTheme.titleLarge))),
          if (v['status'] == 'approved' && data['public_url'] != null)
            TextButton.icon(onPressed: () => copy(context, data['public_url'] as String, 'Profile link copied'), icon: const Icon(Icons.share), label: const Text('Share profile')),
        ]),
        if (v['description'] != null) Text(v['description'] as String),
        TextButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VendorEditScreen())).then((_) => reload()), icon: const Icon(Icons.edit_outlined), label: const Text('Edit details')),
        const Divider(height: 24),
        Row(children: [
          Expanded(child: Text('Portfolio (${media.length})', style: th.textTheme.titleMedium)),
          FilledButton.icon(onPressed: uploading ? null : upload, icon: const Icon(Icons.add_photo_alternate_outlined), label: Text(uploading ? 'Uploading…' : 'Add photos / videos')),
        ]),
        const Text('Only your own real weddings: no stock or borrowed photos. We check.'),
        const SizedBox(height: 8),
        GridView.extent(
          maxCrossAxisExtent: 160,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (final m in media)
              Stack(fit: StackFit.expand, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: m['kind'] == 'photo' ? Image.network(m['url'] as String, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12)) : const ColoredBox(color: Colors.black26, child: Icon(Icons.play_circle_outline, size: 40)),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: IconButton(
                    style: IconButton.styleFrom(backgroundColor: Colors.black45),
                    color: Colors.white,
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Remove',
                    onPressed: () async {
                      await guard(context, () => s.api.delete('/vendor/media/${m['id']}'));
                      await reload();
                    },
                  ),
                ),
              ]),
          ],
        ),
        const Divider(height: 32),
        Row(children: [
          Expanded(child: Text('Packages', style: th.textTheme.titleMedium)),
          OutlinedButton.icon(onPressed: () => editPackage(), icon: const Icon(Icons.add), label: const Text('Add package')),
        ]),
        for (final p in packages)
          Card(
            child: ListTile(
              title: Text(p['name'] as String),
              subtitle: Text([if (p['includes'] != null) p['includes'], 'from ${lkr(num.parse('${p['starting_lkr']}'))}${p['negotiable'] == true ? ' (negotiable)' : ''}'].join('\n')),
              onTap: () => editPackage(p as Map<String, dynamic>),
            ),
          ),
      ]),
    );
  }
}

class VendorEditScreen extends StatefulWidget {
  const VendorEditScreen({super.key});
  @override
  State<VendorEditScreen> createState() => _VendorEditScreenState();
}

class _VendorEditScreenState extends State<VendorEditScreen> {
  late final v = AppScope.read(context).vendor?['vendor'] as Map<String, dynamic>? ?? {};
  late final name = TextEditingController(text: v['business_name'] ?? '');
  late final about = TextEditingController(text: v['description'] ?? '');
  late final phone = TextEditingController(text: v['phone'] ?? '');
  late final areas = <String>{...((v['service_areas'] as List?)?.cast<String>() ?? [])};

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Business details')),
      body: PageBody(maxWidth: 640, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Business name')),
        const SizedBox(height: 12),
        TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone / WhatsApp', helperText: 'Changing it needs re-verification')),
        const SizedBox(height: 12),
        TextField(controller: about, maxLines: 6, decoration: const InputDecoration(labelText: 'About')),
        const SizedBox(height: 12),
        const Text('Districts you serve'),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final d in sriLankaDistricts) FilterChip(label: Text(d), selected: areas.contains(d), onSelected: (on) => setState(() => on ? areas.add(d) : areas.remove(d)))]),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () async {
            final body = {'business_name': name.text.trim(), 'description': about.text.trim(), 'service_areas': areas.toList(), if (phone.text.trim() != (v['phone'] ?? '')) 'phone': phone.text.trim()};
            final r = await guard(context, () => s.api.patch('/vendor', body));
            if (r != null && context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ]),
    );
  }
}

class _Availability extends StatefulWidget {
  const _Availability();
  @override
  State<_Availability> createState() => _AvailabilityState();
}

class _AvailabilityState extends State<_Availability> {
  Set<String>? blocked;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final r = await guard(context, () => AppScope.read(context).api.get('/vendor/availability'));
    if (r != null && mounted) setState(() => blocked = {...(r['blocked'] as List).cast<String>()});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (blocked == null) return const Center(child: CircularProgressIndicator());
    return PageBody(children: [
      Semantics(header: true, child: Text('Booked dates', style: Theme.of(context).textTheme.titleLarge)),
      const Text('Couples searching for these dates won\'t see you, so you only get enquiries you can take.'),
      const SizedBox(height: 12),
      FilledButton.icon(
        icon: const Icon(Icons.event_busy),
        label: const Text('Mark a date as booked'),
        onPressed: () async {
          final d = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime(DateTime.now().year + 3));
          if (d == null || !context.mounted) return;
          await guard(context, () => s.api.put('/vendor/availability', {'days': [d.toIso8601String().substring(0, 10)]}));
          await load();
        },
      ),
      const SizedBox(height: 12),
      for (final d in (blocked!.toList()..sort()))
        ListTile(
          leading: const Icon(Icons.event_busy),
          title: Text(d),
          trailing: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Free this date',
            onPressed: () async {
              await guard(context, () => s.api.put('/vendor/availability', {'days': [d], 'blocked': false}));
              await load();
            },
          ),
        ),
    ]);
  }
}

class _Stats extends StatefulWidget {
  const _Stats();
  @override
  State<_Stats> createState() => _StatsState();
}

class _StatsState extends State<_Stats> {
  Map<String, dynamic>? stats;
  List<dynamic> reviews = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final s = AppScope.read(context);
    final r = await guard(context, () async => [await s.api.get('/vendor/stats'), await s.api.get('/vendor/reviews')]);
    if (r != null && mounted) setState(() { stats = r[0]; reviews = r[1]['reviews'] as List<dynamic>; });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    if (stats == null) return const Center(child: CircularProgressIndicator());
    final days = (stats!['days'] as List).cast<Map<String, dynamic>>();
    final maxV = days.fold<int>(1, (m, d) => (d['views'] as int) > m ? d['views'] as int : m);
    return RefreshIndicator(
      onRefresh: load,
      child: PageBody(maxWidth: 900, children: [
        StatGrid(cols: isWide(context) ? 4 : 2, children: [
          StatTile('Profile views (30 days)', stats!['views_30d']),
          StatTile('Enquiries (30 days)', stats!['enquiries_30d']),
          StatTile('Average reply', stats!['reply_hours'] == null ? '—' : '${stats!['reply_hours']} h', color: (stats!['reply_hours'] ?? 0) > 24 ? th.colorScheme.error : null),
          StatTile('Booked', stats!['booked']),
          StatTile('Shortlisted', stats!['shortlisted']),
        ]),
        if ((stats!['unanswered'] as int) > 0) Text('${stats!['unanswered']} enquiries are waiting for a reply. Couples choose vendors who answer within a day.', style: TextStyle(color: th.colorScheme.error)),
        const SizedBox(height: 12),
        Text('Profile views, last 14 days', style: th.textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          height: 90,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final d in days)
              Expanded(
                child: Tooltip(
                  message: '${d['day']}: ${d['views']} views',
                  child: Container(margin: const EdgeInsets.symmetric(horizontal: 2), height: 4 + 80 * (d['views'] as int) / maxV, decoration: BoxDecoration(color: th.colorScheme.primary, borderRadius: BorderRadius.circular(3))),
                ),
              ),
          ]),
        ),
        // Sold only in the web panel: in the iOS/Android apps a paid listing would have to be an
        // in-app purchase (App Store 3.1.1), and the apps may not point to a web checkout either.
        if (kIsWeb) const _Promotions(),
        const Divider(height: 32),
        Semantics(header: true, child: Text('Reviews', style: th.textTheme.titleLarge)),
        if (reviews.isEmpty) const Text('Reviews come from couples who contacted you in the app, after their wedding. Ask them from the enquiry screen.'),
        for (final r in reviews)
          Card(
            child: ListTile(
              title: Text('${'★' * (r['rating'] as int)}  ${r['partner1']} & ${r['partner2']}'),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (r['body'] != null) Text(r['body'] as String),
                if (r['reply'] != null) Text('Your reply: ${r['reply']}', style: const TextStyle(fontStyle: FontStyle.italic)),
              ]),
              trailing: r['reply'] == null
                  ? TextButton(
                      onPressed: () async {
                        final c = TextEditingController();
                        final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('Public reply'), content: TextField(controller: c, maxLines: 4), actions: [FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Post'))]));
                        if (ok == true && context.mounted) {
                          await guard(context, () => s.api.post('/vendor/reviews/${r['id']}/reply', {'reply': c.text}));
                          await load();
                        }
                      },
                      child: const Text('Reply'),
                    )
                  : null,
            ),
          ),
      ]),
    );
  }
}

/// Featured placement (by the month) and the annual verified badge, bought by the vendor.
class _Promotions extends StatefulWidget {
  const _Promotions();
  @override
  State<_Promotions> createState() => _PromotionsState();
}

class _PromotionsState extends State<_Promotions> {
  Map<String, dynamic>? p;
  int months = 1;
  Map<String, dynamic>? bank;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final r = await guard(context, () => AppScope.read(context).api.get('/vendor/promotions'));
    if (r != null && mounted) setState(() => p = r);
  }

  Future<void> buy(String product, String method) async {
    final r = await guard(context, () => AppScope.read(context).api.post('/vendor/checkout', {'product': product, 'months': months, 'method': method}));
    if (r == null || !mounted) return;
    if (method == 'bank_transfer') {
      setState(() => bank = r);
    } else {
      await openUrl(r['checkoutUrl'] as String);
    }
  }

  String until(String? iso) {
    if (iso == null) return '';
    final d = DateTime.parse(iso).toLocal();
    return d.isAfter(DateTime.now()) ? 'until ${d.day}/${d.month}/${d.year}' : '';
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    if (p == null || p!['open'] != true) return const SizedBox.shrink();
    final prices = p!['prices'] as Map<String, dynamic>;
    final featuredUntil = until(p!['featured_until'] as String?);
    final verifiedUntil = until(p!['verified_until'] as String?);
    final slots = p!['featured_slots_left'] as int;
    final pending = [for (final x in p!['payments'] as List) if (x['status'] == 'pending' && x['method'] == 'bank_transfer') x];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Divider(height: 32),
      Semantics(header: true, child: Text('Get more enquiries', style: th.textTheme.titleLarge)),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Featured placement ${featuredUntil.isEmpty ? '' : '· $featuredUntil'}', style: th.textTheme.titleMedium),
            const Text('Shown first in your category, always labelled "Featured". A few places per category.'),
            const SizedBox(height: 8),
            if (slots < 1)
              Text('All featured places in your category are taken right now.', style: TextStyle(color: th.colorScheme.error))
            else
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                DropdownButton<int>(
                  value: months,
                  items: [for (final m in const [1, 3, 6, 12]) DropdownMenuItem(value: m, child: Text('$m month${m == 1 ? '' : 's'} · LKR ${(prices['featured_month_lkr'] as int) * m}'))],
                  onChanged: (v) => setState(() => months = v!),
                ),
                FilledButton(onPressed: () => buy('vendor_featured', 'gateway'), child: Text(featuredUntil.isEmpty ? 'Pay by card' : 'Extend by card')),
                OutlinedButton(onPressed: () => buy('vendor_featured', 'bank_transfer'), child: const Text('Bank transfer')),
              ]),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Verified badge ${verifiedUntil.isEmpty ? '' : '· $verifiedUntil'}', style: th.textTheme.titleMedium),
            Text('A "Verified" label on your profile and in search for 12 months · LKR ${prices['verified_year_lkr']}.'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(onPressed: () => buy('vendor_verified', 'gateway'), child: Text(verifiedUntil.isEmpty ? 'Pay by card' : 'Renew by card')),
              OutlinedButton(onPressed: () => buy('vendor_verified', 'bank_transfer'), child: const Text('Bank transfer')),
            ]),
          ]),
        ),
      ),
      if (bank != null)
        Card(
          color: th.colorScheme.secondaryContainer,
          child: ListTile(title: Text('Transfer LKR ${bank!['amount_lkr']} with reference ${bank!['reference']}'), subtitle: Text(bank!['instructions'] as String)),
        ),
      for (final x in pending) Text('Waiting for transfer ${x['reference']} (LKR ${x['amount_lkr']})', style: th.textTheme.bodySmall),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: load, icon: const Icon(Icons.refresh), label: const Text('I have paid: refresh'))),
    ]);
  }
}

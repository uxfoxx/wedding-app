import 'package:flutter/material.dart';

import '../ui.dart';
import 'budget.dart' show lkr;

/// Vendors for a wedding: suggested for you, browse, shortlist & compare, and contacted vendors.
class VendorsScreen extends StatefulWidget {
  const VendorsScreen({super.key});
  @override
  State<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends State<VendorsScreen> {
  List<dynamic> categories = [];
  String category = 'photographers';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final r = await guard(context, () => AppScope.read(context).api.get('/vendor-categories'));
      if (r != null && mounted) setState(() => categories = r['categories'] as List<dynamic>);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Vendors'),
          bottom: const TabBar(isScrollable: true, tabs: [Tab(text: 'Suggested'), Tab(text: 'Browse'), Tab(text: 'Shortlist'), Tab(text: 'Contacted')]),
        ),
        body: Column(children: [
          if (categories.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
                for (final c in categories)
                  Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(c['name'] as String), selected: category == c['id'], onSelected: (_) => setState(() => category = c['id'] as String))),
              ]),
            ),
          Expanded(
            child: TabBarView(children: [
              _VendorList(key: ValueKey('s$category'), path: (s) => '/weddings/${s.weddingId}/vendor-suggestions', query: {'category': category}, explain: true),
              _Browse(key: ValueKey('b$category'), category: category),
              const _Shortlist(),
              const ContactedVendors(),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Browse extends StatefulWidget {
  const _Browse({super.key, required this.category});
  final String category;
  @override
  State<_Browse> createState() => _BrowseState();
}

class _BrowseState extends State<_Browse> {
  String? district;
  String? language;
  String? maxPrice;
  bool onMyDate = true;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final events = (s.summary?['events'] as List?) ?? [];
    final date = events.isNotEmpty ? isoToSl(events.first['starts_at'] as String).toIso8601String().substring(0, 10) : null;
    final query = {
      'category': widget.category,
      'district': ?district,
      'language': ?language,
      'max_price': ?maxPrice,
      if (onMyDate && date != null) 'date': date,
    };
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          DropdownButton<String?>(
            value: district,
            hint: const Text('Any district'),
            items: [const DropdownMenuItem(value: null, child: Text('Any district')), for (final d in const ['Colombo', 'Gampaha', 'Kalutara', 'Kandy', 'Galle', 'Matara', 'Kurunegala', 'Jaffna', 'Batticaloa', 'Trincomalee', 'Negombo']) DropdownMenuItem(value: d, child: Text(d))],
            onChanged: (v) => setState(() => district = v),
          ),
          DropdownButton<String?>(
            value: maxPrice,
            hint: const Text('Any price'),
            items: const [DropdownMenuItem(value: null, child: Text('Any price')), DropdownMenuItem(value: '50000', child: Text('Up to LKR 50,000')), DropdownMenuItem(value: '150000', child: Text('Up to LKR 150,000')), DropdownMenuItem(value: '300000', child: Text('Up to LKR 300,000')), DropdownMenuItem(value: '1000000', child: Text('Up to LKR 1,000,000'))],
            onChanged: (v) => setState(() => maxPrice = v),
          ),
          DropdownButton<String?>(
            value: language,
            hint: const Text('Any language'),
            items: const [DropdownMenuItem(value: null, child: Text('Any language')), DropdownMenuItem(value: 'si', child: Text('සිංහල')), DropdownMenuItem(value: 'ta', child: Text('தமிழ்')), DropdownMenuItem(value: 'en', child: Text('English'))],
            onChanged: (v) => setState(() => language = v),
          ),
          if (date != null) FilterChip(label: Text('Free on $date'), selected: onMyDate, onSelected: (v) => setState(() => onMyDate = v)),
        ]),
      ),
      Expanded(child: _VendorList(key: ValueKey(query.toString()), path: (_) => '/vendors', query: query)),
    ]);
  }
}

class _VendorList extends StatefulWidget {
  const _VendorList({super.key, required this.path, required this.query, this.explain = false});
  final String Function(dynamic s) path;
  final Map<String, String> query;
  final bool explain;
  @override
  State<_VendorList> createState() => _VendorListState();
}

class _VendorListState extends State<_VendorList> {
  Map<String, dynamic>? data;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final s = AppScope.read(context);
    final r = await guard(context, () => s.api.get(widget.path(s), widget.query));
    if (r != null && mounted) setState(() => data = r);
  }

  @override
  Widget build(BuildContext context) {
    if (data == null) return const Center(child: CircularProgressIndicator());
    final list = (data!['vendors'] as List).cast<Map<String, dynamic>>();
    final based = data!['based_on'] as Map<String, dynamic>?;
    return RefreshIndicator(
      onRefresh: load,
      child: PageBody(maxWidth: 1000, children: [
        if (widget.explain && based != null)
          Text('Serving ${based['district'] ?? 'your area'}${based['date'] != null ? ', free on ${based['date']}' : ''}${based['budget_lkr'] != null ? ', near your budget of ${lkr(based['budget_lkr'] as num)}' : ''}.'),
        if (list.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No vendors match yet. We add checked vendors every week.', textAlign: TextAlign.center)),
        Wrap(spacing: 12, runSpacing: 12, children: [for (final v in list) SizedBox(width: isWide(context) ? 300 : double.infinity, child: VendorCard(v: v))]),
      ]),
    );
  }
}

class VendorCard extends StatelessWidget {
  const VendorCard({super.key, required this.v, this.trailing});
  final Map<String, dynamic> v;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VendorProfileScreen(slug: v['slug'] as String))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: v['cover_url'] != null
                ? Image.network(v['cover_url'] as String, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12))
                : ColoredBox(color: th.colorScheme.surfaceContainerHighest, child: const Icon(Icons.photo_camera_outlined, size: 40)),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, children: [
                // Featured, verified and checked are always labelled.
                if (v['featured'] == true) const Chip(label: Text('Featured'), visualDensity: VisualDensity.compact),
                if (v['verified_badge'] == true) const Chip(avatar: Icon(Icons.verified, size: 16), label: Text('Verified'), visualDensity: VisualDensity.compact),
                if (v['checked'] == true && v['verified_badge'] != true) const Chip(label: Text('Checked by our team'), visualDensity: VisualDensity.compact),
                if (v['fits_budget'] == false) const Chip(label: Text('Above your budget'), visualDensity: VisualDensity.compact),
              ]),
              Row(children: [
                Expanded(child: Text(v['business_name'] as String, style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                ?trailing,
              ]),
              Text([
                v['district'],
                if (v['rating'] != null) '★ ${v['rating']} (${v['reviews']})',
                if (v['reply_hours'] != null) 'replies in ~${(v['reply_hours'] as num).ceil()} h',
              ].join(' · ')),
              if (v['starting_lkr'] != null) Text('From ${lkr(num.parse('${v['starting_lkr']}'))}', style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class VendorProfileScreen extends StatefulWidget {
  const VendorProfileScreen({super.key, required this.slug});
  final String slug;
  @override
  State<VendorProfileScreen> createState() => _VendorProfileScreenState();
}

class _VendorProfileScreenState extends State<VendorProfileScreen> {
  Map<String, dynamic>? data;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final r = await guard(context, () => AppScope.read(context).api.get('/vendors/${widget.slug}'));
      if (r != null && mounted) setState(() => data = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    if (data == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final v = data!['vendor'] as Map<String, dynamic>;
    final hasWedding = s.weddingId != null && s.canEditAll;
    return Scaffold(
      appBar: AppBar(title: Text(v['business_name'] as String), actions: [
        if (s.isPlanner)
          IconButton(
            tooltip: 'Add to my preferred vendors',
            icon: const Icon(Icons.favorite_border),
            onPressed: () async {
              final r = await guard(context, () => s.api.put('/planner/preferred-vendors/${v['id']}', {'preferred': true}));
              if (r != null && context.mounted) toast(context, 'Added to your preferred vendors');
            },
          ),
      ]),
      bottomNavigationBar: hasWedding
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('Shortlist'),
                      onPressed: () async {
                        final r = await guard(context, () => s.api.put('/weddings/${s.weddingId}/shortlist/${v['id']}', {}));
                        if (r != null && context.mounted) toast(context, 'Added to your shortlist');
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('enquire'),
                      icon: const Icon(Icons.send),
                      label: const Text('Enquire'),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EnquiryComposer(vendors: [v]))),
                    ),
                  ),
                ]),
              ),
            )
          : null,
      body: PageBody(maxWidth: 900, children: [
        Text('${v['district']} · ${v['years_active'] ?? '?'} years · ${((v['languages'] as List?) ?? []).join(', ')}'),
        if (v['rating'] != null) Text('★ ${v['rating']} from ${v['reviews']} couples'),
        if (v['description'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(v['description'] as String)),
        const SizedBox(height: 12),
        GridView.extent(
          maxCrossAxisExtent: 200,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (final m in data!['media'] as List)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: m['kind'] == 'photo'
                    ? Image.network(m['url'] as String, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12))
                    : InkWell(onTap: () => openUrl(m['url'] as String), child: const ColoredBox(color: Colors.black26, child: Icon(Icons.play_circle_outline, size: 40))),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Packages', style: th.textTheme.titleLarge),
        for (final p in data!['packages'] as List)
          Card(child: ListTile(title: Text(p['name'] as String), subtitle: Text([if (p['includes'] != null) p['includes'], if (p['addons'] != null) 'Add-ons: ${p['addons']}'].join('\n')), trailing: Text('from ${lkr(num.parse('${p['starting_lkr']}'))}${p['negotiable'] == true ? '\nnegotiable' : ''}', textAlign: TextAlign.right))),
        const SizedBox(height: 16),
        Text('Reviews', style: th.textTheme.titleLarge),
        const Text('Only from couples who planned their wedding in the app and contacted this vendor.'),
        for (final r in data!['reviews'] as List)
          Card(child: ListTile(title: Text('★' * (r['rating'] as int)), subtitle: Text([r['body'] ?? '', if (r['reply'] != null) 'Reply: ${r['reply']}'].join('\n')))),
      ]),
    );
  }
}

class _Shortlist extends StatefulWidget {
  const _Shortlist();
  @override
  State<_Shortlist> createState() => _ShortlistState();
}

class _ShortlistState extends State<_Shortlist> {
  List<dynamic>? list;
  final picked = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final s = AppScope.read(context);
    final r = await guard(context, () => s.api.get('/weddings/${s.weddingId}/shortlist'));
    if (r != null && mounted) setState(() => list = r['vendors'] as List<dynamic>);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (list == null) return const Center(child: CircularProgressIndicator());
    if (list!.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Save vendors you like, then compare up to three side by side and contact them in one go.', textAlign: TextAlign.center)));
    final chosen = list!.where((v) => picked.contains(v['id'])).cast<Map<String, dynamic>>().toList();
    return RefreshIndicator(
      onRefresh: load,
      child: PageBody(maxWidth: 1000, children: [
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(onPressed: chosen.length < 2 || chosen.length > 3 ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompareScreen(vendors: chosen))), icon: const Icon(Icons.compare_arrows), label: Text('Compare (${chosen.length}/3)')),
          FilledButton.icon(onPressed: chosen.isEmpty ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EnquiryComposer(vendors: chosen))), icon: const Icon(Icons.send), label: Text('Enquire (${chosen.length})')),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final v in list!)
            SizedBox(
              width: isWide(context) ? 300 : double.infinity,
              child: VendorCard(
                v: v as Map<String, dynamic>,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(value: picked.contains(v['id']), onChanged: (on) => setState(() => on == true ? picked.add(v['id'] as String) : picked.remove(v['id']))),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.bookmark_remove_outlined),
                    onPressed: () async {
                      await guard(context, () => s.api.delete('/weddings/${s.weddingId}/shortlist/${v['id']}'));
                      await load();
                    },
                  ),
                ]),
              ),
            ),
        ]),
      ]),
    );
  }
}

class CompareScreen extends StatelessWidget {
  const CompareScreen({super.key, required this.vendors});
  final List<Map<String, dynamic>> vendors;
  @override
  Widget build(BuildContext context) {
    final rows = <(String, String Function(Map<String, dynamic>))>[
      ('From', (v) => v['starting_lkr'] != null ? lkr(num.parse('${v['starting_lkr']}')) : '—'),
      ('Rating', (v) => v['rating'] != null ? '★ ${v['rating']} (${v['reviews']})' : 'No reviews yet'),
      ('Replies in', (v) => v['reply_hours'] != null ? '~${(v['reply_hours'] as num).ceil()} hours' : '—'),
      ('Based in', (v) => '${v['district']}'),
      ('Years', (v) => '${v['years_active'] ?? '—'}'),
      ('Languages', (v) => ((v['languages'] as List?) ?? []).join(', ')),
      ('Packages', (v) => ((v['packages'] as List?) ?? []).map((p) => '${p['name']}: ${lkr(num.parse('${p['starting_lkr']}'))}').join('\n')),
      ('Labels', (v) => [if (v['featured'] == true) 'Featured', if (v['verified_badge'] == true) 'Verified', if (v['checked'] == true) 'Checked'].join(', ')),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Compare')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            dataRowMaxHeight: 120,
            columns: [const DataColumn(label: Text('')), for (final v in vendors) DataColumn(label: SizedBox(width: 180, child: Text(v['business_name'] as String, style: const TextStyle(fontWeight: FontWeight.w700))))],
            rows: [for (final r in rows) DataRow(cells: [DataCell(Text(r.$1)), for (final v in vendors) DataCell(SizedBox(width: 180, child: Text(r.$2(v))))])],
          ),
        ),
      ),
    );
  }
}

/// One enquiry to several vendors; it carries the wedding date, venue, guest count and (optionally) budget.
class EnquiryComposer extends StatefulWidget {
  const EnquiryComposer({super.key, required this.vendors});
  final List<Map<String, dynamic>> vendors;
  @override
  State<EnquiryComposer> createState() => _EnquiryComposerState();
}

class _EnquiryComposerState extends State<EnquiryComposer> {
  final msg = TextEditingController(text: 'Hello! We are getting married and would love to know if you are available on our date, and what your packages include.');
  final budget = TextEditingController();
  bool shareBudget = false;
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final events = (s.summary?['events'] as List?) ?? [];
    final c = s.summary?['counts'] as Map<String, dynamic>? ?? {};
    return Scaffold(
      appBar: AppBar(title: Text('Enquire (${widget.vendors.length})')),
      body: PageBody(maxWidth: 640, children: [
        Text('To: ${widget.vendors.map((v) => v['business_name']).join(', ')}'),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Sent with your enquiry, so nobody has to explain twice:', style: TextStyle(fontWeight: FontWeight.w600)),
              if (events.isNotEmpty) Text('Date: ${fmtSl(events.first['starts_at'] as String)}'),
              if (events.isNotEmpty && events.first['venue'] != null) Text('Venue: ${events.first['venue']}'),
              Text('Guests: about ${s.wedding['expected_guests'] ?? ((c['seats'] ?? 0) as int)}'),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        TextField(key: const Key('enqMsg'), controller: msg, maxLines: 6, decoration: const InputDecoration(labelText: 'Message')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Share my budget'), subtitle: const Text('Optional. Vendors see it only if you turn this on.'), value: shareBudget, onChanged: (v) => setState(() => shareBudget = v)),
        if (shareBudget) TextField(controller: budget, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Budget for this (LKR)')),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('sendEnquiry'),
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  final r = await guard(context, () => s.api.post('/weddings/${s.weddingId}/enquiries', {
                        'vendor_ids': widget.vendors.map((v) => v['id']).toList(), 'message': msg.text.trim(),
                        'share_budget': shareBudget, if (shareBudget) 'budget_lkr': num.tryParse(budget.text.replaceAll(',', '')),
                      }));
                  if (!context.mounted) return;
                  setState(() => busy = false);
                  if (r != null) {
                    toast(context, 'Sent to ${r['sent']} vendor${r['sent'] == 1 ? '' : 's'}. Track replies under Vendors → Contacted.');
                    Navigator.pop(context);
                  }
                },
          child: const Text('Send enquiry'),
        ),
      ]),
    );
  }
}

/// Track each vendor: contacted → quoted → booked / rejected. Booked vendors go into the budget and run sheet.
class ContactedVendors extends StatefulWidget {
  const ContactedVendors({super.key});
  @override
  State<ContactedVendors> createState() => _ContactedVendorsState();
}

class _ContactedVendorsState extends State<ContactedVendors> {
  List<dynamic>? list;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final s = AppScope.read(context);
    final r = await guard(context, () => s.api.get('/weddings/${s.weddingId}/enquiries'));
    if (r != null && mounted) setState(() => list = r['enquiries'] as List<dynamic>);
  }

  Future<void> setStatus(Map e, String status) async {
    final s = AppScope.read(context);
    num? price;
    if (status == 'booked') {
      final c = TextEditingController();
      final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('Agreed price (optional)'), content: TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'LKR')), actions: [FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save'))]));
      if (ok != true) return;
      price = num.tryParse(c.text.replaceAll(',', ''));
    }
    if (!mounted) return;
    await guard(context, () => s.api.patch('/weddings/${s.weddingId}/enquiries/${e['id']}', {'status': status, 'price_lkr': ?price}));
    if (status == 'booked' && mounted) toast(context, 'Added to your budget and run sheet.');
    await load();
  }

  Future<void> review(Map e) async {
    final s = AppScope.read(context);
    int rating = 5;
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('Review ${e['business_name']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (var i = 1; i <= 5; i++) IconButton(icon: Icon(i <= rating ? Icons.star : Icons.star_border, color: Brand.gold), onPressed: () => set(() => rating = i))]),
            TextField(controller: body, maxLines: 4, decoration: const InputDecoration(hintText: 'How was it?')),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Post review'))],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final r = await guard(context, () => s.api.post('/weddings/${s.weddingId}/reviews', {'vendor_id': e['vendor_id'], 'rating': rating, 'body': body.text.trim()}));
    if (r != null && mounted) toast(context, 'Thank you for your review!');
    await load();
  }

  Future<void> complain(Map e) async {
    final s = AppScope.read(context);
    final body = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: Text('Report a problem with ${e['business_name']}'), content: TextField(controller: body, maxLines: 5, decoration: const InputDecoration(hintText: 'What happened? Our team will look into it.')), actions: [FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Send to our team'))]));
    if (ok != true || body.text.trim().isEmpty || !mounted) return;
    final r = await guard(context, () => s.api.post('/weddings/${s.weddingId}/complaints', {'vendor_id': e['vendor_id'], 'body': body.text.trim()}));
    if (r != null && mounted) toast(context, 'Sent. Our team will contact you.');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    if (list == null) return const Center(child: CircularProgressIndicator());
    if (list!.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Vendors you contact appear here with their replies.', textAlign: TextAlign.center)));
    final events = (s.summary?['events'] as List?) ?? [];
    final after = events.isNotEmpty && DateTime.parse(events.last['starts_at'] as String).isBefore(DateTime.now());
    return RefreshIndicator(
      onRefresh: load,
      child: PageBody(maxWidth: 900, children: [
        for (final e in list!)
          Card(
            child: ExpansionTile(
              title: Text(e['business_name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${e['couple_status']} · vendor: ${e['vendor_status']}'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                for (final m in e['messages'] as List)
                  Align(
                    alignment: m['from'] == 'couple' ? Alignment.centerRight : Alignment.centerLeft,
                    child: Card(color: m['from'] == 'couple' ? th.colorScheme.primaryContainer : null, child: Padding(padding: const EdgeInsets.all(10), child: Text(m['body'] as String))),
                  ),
                if (s.canEditAll) _ReplyBox(onSend: (t) async {
                  await guard(context, () => s.api.post('/weddings/${s.weddingId}/enquiries/${e['id']}/messages', {'body': t}));
                  await load();
                }),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final st in const ['quoted', 'booked', 'rejected']) ChoiceChip(label: Text(st), selected: e['couple_status'] == st, onSelected: s.canEditAll ? (_) => setStatus(e as Map, st) : null),
                  if (e['whatsapp'] != null) ActionChip(avatar: const Icon(Icons.chat, size: 16), label: const Text('WhatsApp'), onPressed: () => openUrl(e['whatsapp'] as String)),
                  if (after && e['reviewed'] != true) ActionChip(avatar: const Icon(Icons.star_outline, size: 16), label: const Text('Write a review'), onPressed: () => review(e as Map)),
                  ActionChip(avatar: const Icon(Icons.flag_outlined, size: 16), label: const Text('Report a problem'), onPressed: () => complain(e as Map)),
                ]),
              ],
            ),
          ),
      ]),
    );
  }
}

class _ReplyBox extends StatefulWidget {
  const _ReplyBox({required this.onSend});
  final Future<void> Function(String) onSend;
  @override
  State<_ReplyBox> createState() => _ReplyBoxState();
}

class _ReplyBoxState extends State<_ReplyBox> {
  final c = TextEditingController();
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: TextField(controller: c, decoration: const InputDecoration(hintText: 'Reply…', isDense: true))),
        IconButton(
          icon: const Icon(Icons.send),
          onPressed: () async {
            if (c.text.trim().isEmpty) return;
            await widget.onSend(c.text.trim());
            c.clear();
          },
        ),
      ]);
}

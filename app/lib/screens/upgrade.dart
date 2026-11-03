import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../ui.dart';

/// Wedding Pass. In the iOS and Android apps it is sold through the App Store / Google Play
/// (store rules require it, and the app must not point to outside payment). In the web panel
/// it is sold by card through the local gateway, or by bank transfer, at a lower price.
class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({super.key});
  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

const passProductId = 'wedding_pass';

class _UpgradeScreenState extends State<UpgradeScreen> {
  Map<String, dynamic>? billing;
  Map<String, dynamic>? bankTransfer;
  ProductDetails? product;
  StreamSubscription<List<PurchaseDetails>>? sub;
  bool busy = false;
  bool get useStore => !kIsWeb;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
    if (useStore) {
      sub = InAppPurchase.instance.purchaseStream.listen(onPurchases);
      InAppPurchase.instance.queryProductDetails({passProductId}).then((r) {
        if (mounted && r.productDetails.isNotEmpty) setState(() => product = r.productDetails.first);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  Map<String, dynamic>? quote;
  final code = TextEditingController();

  Future<void> load() async {
    final s = AppScope.read(context);
    final r = await guard(context, () => s.api.get('/weddings/${s.weddingId}/billing'));
    final qt = await s.api.get('/weddings/${s.weddingId}/quote').catchError((_) => <String, dynamic>{});
    if (r != null && mounted) setState(() { billing = r; quote = qt.isEmpty ? null : qt; });
  }

  Future<void> onPurchases(List<PurchaseDetails> list) async {
    final s = AppScope.read(context);
    for (final p in list) {
      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
        // The server verifies the receipt with Apple/Google and unlocks the wedding. Never trust the device.
        await guard(context, () => s.api.post('/weddings/${s.weddingId}/iap', {
              'store': defaultTargetPlatform == TargetPlatform.iOS ? 'app_store' : 'play_store',
              'receipt': p.verificationData.serverVerificationData,
              'product_id': p.productID,
            }));
        if (p.pendingCompletePurchase) await InAppPurchase.instance.completePurchase(p);
        await s.refresh();
      } else if (p.status == PurchaseStatus.error && mounted) {
        toast(context, p.error?.message ?? 'Purchase failed');
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> buyInStore() async {
    final s = AppScope.read(context);
    if (product == null) {
      toast(context, 'The Wedding Pass is not available in the store yet.');
      return;
    }
    setState(() => busy = true);
    // Consumable: a couple may buy a pass for more than one wedding (e.g. a sibling's).
    await InAppPurchase.instance.buyConsumable(purchaseParam: PurchaseParam(productDetails: product!, applicationUserName: s.weddingId));
  }

  Future<void> checkout(String method) async {
    final s = AppScope.read(context);
    setState(() => busy = true);
    final r = await guard(context, () => s.api.post('/weddings/${s.weddingId}/checkout', {'product': 'wedding_pass', 'method': method}));
    if (mounted) setState(() => busy = false);
    if (r == null) return;
    if (method == 'bank_transfer') {
      setState(() => bankTransfer = r);
    } else {
      await openUrl(r['checkoutUrl'] as String);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    final prices = billing?['prices'] as Map<String, dynamic>?;
    final paid = s.isPaid;
    final rows = const [
      ('Guests', 'Up to 50', 'Unlimited'),
      ('Events', '1', 'Poruwa, reception, homecoming…'),
      ('Designs', '5', 'All, with opening animations'),
      ('RSVP with meals & plus-ones', 'Yes', 'Yes'),
      ('"Made with" footer', 'Shown', 'Removed'),
      ('Export for venue & caterer', '—', 'Excel / PDF'),
      ('Access', 'Until the wedding', '12 months after, then keepsake'),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(s.t('pass'))),
      body: SafeArea(
        child: PageBody(maxWidth: 640, children: [
          Text(paid ? 'You have the Wedding Pass' : s.t('upgrade'), style: th.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('One payment for this wedding, all its events. No subscription.', style: th.textTheme.bodyLarge),
          const SizedBox(height: 16),
          Table(
            columnWidths: const {0: FlexColumnWidth(1.4), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1.4)},
            children: [
              TableRow(children: [const SizedBox(), Text(s.t('free'), style: th.textTheme.titleSmall), Text(s.t('pass'), style: th.textTheme.titleSmall)]),
              for (final r in rows)
                TableRow(children: [
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(r.$1)),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(r.$2)),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(r.$3, style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
            ],
          ),
          const SizedBox(height: 20),
          if (!paid && billing != null) ...[
            if (useStore)
              FilledButton(onPressed: busy ? null : buyInStore, child: Text(product != null ? 'Buy for ${product!.price}' : 'Buy for LKR ${prices!['passAppLkr']}'))
            else ...[
              if (quote != null && ((quote!['discount'] as int) > 0 || (quote!['credits'] as int) > 0))
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Price: LKR ${quote!['list']}'),
                      if ((quote!['discount'] as int) > 0) Text('${quote!['reason']}: − LKR ${quote!['discount']}'),
                      if ((quote!['credits'] as int) > 0) Text('Your credit: − LKR ${quote!['credits']}'),
                      Text('You pay: LKR ${quote!['total']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              if (s.role == 'owner')
                Row(children: [
                  Expanded(child: TextField(controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Friend or partner code', isDense: true))),
                  TextButton(
                    onPressed: () async {
                      final r = await guard(context, () => s.api.post('/weddings/${s.weddingId}/code', {'code': code.text.trim()}));
                      if (r != null) await load();
                    },
                    child: const Text('Apply'),
                  ),
                ]),
              const SizedBox(height: 8),
              FilledButton(key: const Key('payCard'), onPressed: busy ? null : () => checkout('gateway'), child: Text('Pay by card: LKR ${quote?['total'] ?? prices!['passWebLkr']}')),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: busy ? null : () => checkout('bank_transfer'), child: const Text('Pay by bank transfer')),
              if (bankTransfer != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Reference: ${bankTransfer!['reference']}', style: th.textTheme.titleMedium),
                      Text('Amount: LKR ${bankTransfer!['amount_lkr']}'),
                      const SizedBox(height: 6),
                      Text(bankTransfer!['instructions'] as String),
                    ]),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            TextButton(onPressed: () => s.refresh().then((_) => load()), child: const Text('I have paid: check again')),
            const SizedBox(height: 4),
            Text('Full refund within 7 days if no invitation has been sent. If the wedding is postponed, we move your pass to the new date.', style: th.textTheme.bodySmall),
          ],
          const Divider(height: 40),
          const _DesignForMe(),
        ]),
      ),
    );
  }
}

/// "Design it for me": a short brief; a designer builds the invitation and the couple approves it.
class _DesignForMe extends StatefulWidget {
  const _DesignForMe();
  @override
  State<_DesignForMe> createState() => _DesignForMeState();
}

class _DesignForMeState extends State<_DesignForMe> {
  final style = TextEditingController();
  final colours = TextEditingController();
  final notes = TextEditingController();
  List<dynamic>? jobs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (jobs == null) load();
  }

  Future<void> load() async {
    final s = AppScope.read(context);
    final r = await s.api.get('/weddings/${s.weddingId}/design-request').catchError((_) => <String, dynamic>{'jobs': []});
    if (mounted) setState(() => jobs = r['jobs'] as List<dynamic>);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(header: true, child: Text('Design it for me', style: th.textTheme.titleLarge)),
      const Text('Tell us what you like and a designer will build your invitation. From LKR 5,000.'),
      const SizedBox(height: 12),
      for (final j in jobs ?? [])
        Card(child: ListTile(title: Text('Request: ${j['status']}'), subtitle: Text('${(j['messages'] as List).isNotEmpty ? (j['messages'] as List).last['text'] : j['brief']['style'] ?? ''}'))),
      if (s.canEditAll) ...[
        TextField(controller: style, decoration: const InputDecoration(labelText: 'Style (traditional, modern, floral…)')),
        const SizedBox(height: 8),
        TextField(controller: colours, decoration: const InputDecoration(labelText: 'Colours')),
        const SizedBox(height: 8),
        TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Anything else')),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            final r = await guard(context, () => s.api.post('/weddings/${s.weddingId}/design-request', {'style': style.text, 'colours': colours.text, 'notes': notes.text}));
            if (r != null && context.mounted) {
              toast(context, 'Request sent. Our team will contact you about payment and timing.');
              await load();
            }
          },
          child: const Text('Send request'),
        ),
      ],
    ]);
  }
}

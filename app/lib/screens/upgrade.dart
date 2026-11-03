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
      ('Events', '1', 'All your events'),
      ('Designs', '5', 'All, with opening animations'),
      ('RSVP with meals & plus-ones', 'Yes', 'Yes'),
      ('"Made with" footer', 'Shown', 'Removed'),
      ('Export for venue & caterer', '—', 'Excel / PDF'),
      ('Access', 'Until the wedding', '12 months after, then keepsake'),
    ];
    final price = useStore ? null : (quote?['total'] ?? prices?['passWebLkr']);
    Widget cell(String t, {bool pass = false}) => Text(
          t,
          style: TextStyle(fontSize: 14, height: 1.3, fontWeight: pass ? FontWeight.w700 : FontWeight.w500, color: pass ? Brand.ink : Brand.ink2),
        );
    return Scaffold(
      appBar: AppBar(title: Text(s.t('pass'))),
      body: SafeArea(
        child: PageBody(maxWidth: 640, padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
            decoration: BoxDecoration(color: Brand.ink, borderRadius: BorderRadius.circular(30)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFFE9B97A), size: 28),
              const SizedBox(height: 18),
              Text(paid ? 'You have the Wedding Pass' : s.t('upgrade'), style: Brand.display(42, color: Brand.paper)),
              const SizedBox(height: 10),
              Text('One payment for this wedding, all its events. No subscription.', style: TextStyle(color: Brand.paper.withValues(alpha: 0.7), fontSize: 16)),
              if (!paid && price != null) ...[
                const SizedBox(height: 22),
                const Flourish(color: Color(0xFFE9B97A), width: 80),
                const SizedBox(height: 18),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('LKR ', style: TextStyle(color: Color(0xFFE9B97A), fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1))),
                  Text('$price', style: Brand.display(58, color: Brand.paper)),
                ]),
                Text('once, for this wedding', style: TextStyle(color: Brand.paper.withValues(alpha: 0.6), fontSize: 14)),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: Row(children: [
                  const Expanded(flex: 13, child: SizedBox()),
                  Expanded(flex: 10, child: Eyebrow(s.t('free'))),
                  Expanded(flex: 13, child: Eyebrow(s.t('pass'), color: Brand.accent)),
                ]),
              ),
              for (final r in rows) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 13, child: Text(r.$1, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.3))),
                    const SizedBox(width: 8),
                    Expanded(flex: 10, child: cell(r.$2)),
                    Expanded(
                      flex: 13,
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Padding(padding: EdgeInsets.only(top: 1, right: 6), child: Icon(Icons.check_rounded, size: 16, color: Brand.accent)),
                        Expanded(child: cell(r.$3, pass: true)),
                      ]),
                    ),
                  ]),
                ),
              ],
            ]),
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
          const SizedBox(height: 12),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('Design it for me', eyebrow: 'From LKR 5,000'),
      const Text('Tell us what you like and a designer will build your invitation.', style: TextStyle(color: Brand.ink2)),
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

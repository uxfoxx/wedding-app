import 'package:flutter/material.dart';

import '../ui.dart';

/// The WhatsApp send queue: one tap opens WhatsApp with the message and personal link ready,
/// the couple taps Send there, and comes back to the next guest. ~300 guests in about 15 minutes.
/// Messages go from the couple's own WhatsApp (free, and not a bulk sender that can be banned).
class SendQueueScreen extends StatefulWidget {
  const SendQueueScreen({super.key, required this.kind});
  final String kind; // invite | reminder
  @override
  State<SendQueueScreen> createState() => _SendQueueScreenState();
}

class _SendQueueScreenState extends State<SendQueueScreen> with WidgetsBindingObserver {
  List<dynamic>? queue;
  int i = 0;
  int sentCount = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> load() async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.get('/weddings/${s.weddingId}/send-queue', {'kind': widget.kind});
      setState(() => queue = r['guests'] as List<dynamic>);
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  Future<void> send(String url) async {
    final s = AppScope.read(context);
    final g = queue![i];
    await openUrl(url);
    if (!mounted) return;
    if (widget.kind == 'invite') {
      // Recorded as "handed to WhatsApp"; the guest opening the page is the real signal.
      await guard(context, () => s.api.post('/weddings/${s.weddingId}/guests/mark-sent', {'guest_ids': [g['id']]}));
    }
    setState(() {
      sentCount++;
      i++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final th = Theme.of(context);
    final title = widget.kind == 'invite' ? s.t('sendInvites') : s.t('followUps');
    Widget body;
    if (error != null) {
      body = EmptyState(icon: Icons.info_outline, title: title, body: error!, action: s.t('back'), onAction: () => Navigator.pop(context));
    } else if (queue == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (i >= queue!.length) {
      body = EmptyState(
        icon: Icons.check_circle_outline,
        title: queue!.isEmpty && sentCount == 0 ? 'Nobody to send to' : s.t('queueDone'),
        body: sentCount > 0 ? '$sentCount sent. Replies appear in the RSVPs tab as guests answer.' : 'Everyone on your list already has their invitation.',
        action: s.t('done'),
        onAction: () async {
          await s.refresh();
          if (context.mounted) Navigator.pop(context);
        },
      );
    } else {
      final g = queue![i] as Map<String, dynamic>;
      body = PageBody(maxWidth: 560, children: [
        LinearProgressIndicator(value: i / queue!.length),
        const SizedBox(height: 8),
        Text('${i + 1} / ${queue!.length}', style: th.textTheme.labelLarge),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text(g['name'] as String, style: th.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
          if (g['vip'] == true) Chip(label: Text(widget.kind == 'reminder' ? s.t('callFirst') : 'VIP')),
        ]),
        Text(g['phone'] as String? ?? 'No number: WhatsApp will ask who to send to'),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: SelectableText(g['text'] as String))),
        const SizedBox(height: 8),
        Text(s.t('queueTip'), style: th.textTheme.bodySmall),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('sendWhatsApp'),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1F8F4E)),
          onPressed: () => send(g['whatsapp'] as String),
          icon: const Icon(Icons.chat),
          label: Text(s.t('sendOnWhatsApp')),
        ),
        const SizedBox(height: 8),
        Row(children: [
          if (g['sms'] != null) Expanded(child: OutlinedButton(onPressed: () => send(g['sms'] as String), child: const Text('SMS'))),
          if (g['sms'] != null) const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: () => copy(context, g['text'] as String, s.t('copied')), child: Text(s.t('copyLink')))),
          const SizedBox(width: 8),
          Expanded(child: TextButton(onPressed: () => setState(() => i++), child: Text(s.t('skip')))),
        ]),
      ]);
    }
    return Scaffold(appBar: AppBar(title: Text(title)), body: SafeArea(child: body));
  }
}

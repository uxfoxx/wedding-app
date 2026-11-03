import 'package:flutter/material.dart';

import '../ui.dart';
import 'planner_tools.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key, required this.onGo});
  final void Function(String key) onGo;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final sum = s.summary!;
    final next = sum['nextStep'] as Map<String, dynamic>;
    final c = sum['counts'] as Map<String, dynamic>;
    final events = sum['events'] as List<dynamic>;

    return RefreshIndicator(
      onRefresh: s.refresh,
      color: Brand.accent,
      child: PageBody(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
        _Hero(event: events.isEmpty ? null : events.first as Map<String, dynamic>),
        const SizedBox(height: 6),
        // Easy Mode: one clear next step.
        _NextStep(label: next['label'] as String, done: next['key'] == 'done', onTap: () => onGo(next['key'] as String)),
        if (s.isAdvanced) ReadinessCard(onGo: onGo),
        if (sum['suggestAdvanced'] == true)
          RowGroup(children: [
            ActionRow(
              icon: Icons.tune_rounded,
              title: s.t('moreControl'),
              subtitle: s.t('moreControlSub'),
              trailing: TextButton(
                onPressed: () => guard(context, () async => s.setSummary(await s.api.patch('/weddings/${s.weddingId}', {'mode': 'advanced'}))),
                child: Text(s.t('switch')),
              ),
            ),
          ]),
        _Progress(guests: c['guests'] as int, sent: c['sent'] as int, opened: c['opened'] as int, replied: c['replied'] as int, onTap: () => onGo('rsvps')),
        if (!s.isPaid)
          Panel(
            onTap: () => onGo('upgrade'),
            color: Brand.ink,
            borderColor: Brand.ink,
            child: Row(children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFFE9B97A), size: 26),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.t('upgrade'), style: Brand.display(26, color: Brand.paper)),
                  const SizedBox(height: 4),
                  Text(s.t('upgradeSub'), style: TextStyle(color: Brand.paper.withValues(alpha: 0.7), fontSize: 14.5)),
                ]),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, color: Brand.paper),
            ]),
          ),
      ]),
    );
  }
}

/// The couple's names, the date and the days left, set like the front of an invitation.
class _Hero extends StatelessWidget {
  const _Hero({this.event});
  final Map<String, dynamic>? event;

  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final w = s.wedding;
    final at = event == null ? null : isoToSl(event!['starts_at'] as String);
    final today = DateTime.now().toUtc().add(slOffset);
    final days = at == null ? null : DateTime.utc(at.year, at.month, at.day).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    final h = at == null ? 0 : (at.hour % 12 == 0 ? 12 : at.hour % 12);
    final cover = ((w['invitation'] as Map?) ?? {})['cover_photo_url'] as String?;
    const soft = Color(0xFFBDB3A4);

    return Container(
      decoration: BoxDecoration(color: Brand.ink, borderRadius: BorderRadius.circular(30)),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        if (cover != null && cover.isNotEmpty)
          Positioned.fill(
            child: Opacity(
              opacity: 0.32,
              child: Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
            ),
          ),
        if (cover != null && cover.isNotEmpty)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Brand.ink.withValues(alpha: 0.35), Brand.ink.withValues(alpha: 0.92)]),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Eyebrow(s.t(w['kind'] as String? ?? 'wedding'), color: const Color(0xFFE9B97A)),
            const SizedBox(height: 14),
            CoupleNames('${w['partner1']}', '${w['partner2']}', size: 50, color: Brand.paper, amp: const Color(0xFFEE8A6E)),
            const SizedBox(height: 22),
            const Flourish(color: Color(0xFFE9B97A), width: 96),
            const SizedBox(height: 22),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: at == null
                    ? const SizedBox()
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${_days[at.weekday - 1]}, ${at.day} ${_months[at.month - 1]}', style: const TextStyle(color: Brand.paper, fontSize: 17, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text('${at.year} · $h:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'am' : 'pm'}', style: const TextStyle(color: soft, fontSize: 14.5)),
                        if (event!['venue'] != null && '${event!['venue']}'.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(children: [
                            const Icon(Icons.place_outlined, size: 16, color: soft),
                            const SizedBox(width: 5),
                            Flexible(child: Text('${event!['venue']}', overflow: TextOverflow.ellipsis, style: const TextStyle(color: soft, fontSize: 14.5))),
                          ]),
                        ],
                      ]),
              ),
              if (days != null && days >= 0)
                Semantics(
                  label: days == 0 ? s.t('today') : '$days ${s.t('daysToGo')}',
                  excludeSemantics: true,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(days == 0 ? '✦' : '$days', style: Brand.display(64, color: Brand.paper)),
                    Text(days == 0 ? s.t('today') : s.t('daysToGo'), style: const TextStyle(color: soft, fontSize: 13, fontWeight: FontWeight.w700)),
                  ]),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _NextStep extends StatelessWidget {
  const _NextStep({required this.label, required this.done, required this.onTap});
  final String label;
  final bool done;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Panel(
      color: Brand.accentSoft,
      borderColor: const Color(0xFFE9C9BD),
      onTap: done ? null : onTap,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Eyebrow(s.t('nextStep'), color: Brand.accent),
            const SizedBox(height: 8),
            Text(label, style: Brand.display(28)),
          ]),
        ),
        if (!done) ...[
          const SizedBox(width: 12),
          IconButton.filled(
            key: const Key('nextStep'),
            tooltip: s.t('next'),
            onPressed: onTap,
            style: IconButton.styleFrom(backgroundColor: Brand.ink, foregroundColor: Brand.paper, fixedSize: const Size(54, 54)),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ]),
    );
  }
}

/// How far the invitations have got: sent, opened, replied, each out of the guest list.
class _Progress extends StatelessWidget {
  const _Progress({required this.guests, required this.sent, required this.opened, required this.replied, required this.onTap});
  final int guests, sent, opened, replied;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    Widget bar(String label, int n, Color color) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Semantics(
            label: '$label: $n of $guests',
            excludeSemantics: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                Text('$n', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(' / $guests', style: const TextStyle(color: Brand.ink2, fontSize: 15)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(value: guests == 0 ? 0 : n / guests, minHeight: 8, color: color, backgroundColor: Brand.sunk),
              ),
            ]),
          ),
        );
    return Panel(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Eyebrow(s.t('guests')),
              const SizedBox(height: 6),
              Text('$guests', style: Brand.display(52)),
            ]),
          ),
          const Icon(Icons.arrow_outward_rounded, color: Brand.ink2),
        ]),
        bar(s.t('sent'), sent, Brand.ink),
        bar(s.t('opened'), opened, Brand.gold),
        bar(s.t('rsvps'), replied, Brand.accent),
      ]),
    );
  }
}

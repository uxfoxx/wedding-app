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
    final th = Theme.of(context);
    final cols = isWide(context) ? 4 : 2;

    return RefreshIndicator(
      onRefresh: s.refresh,
      child: PageBody(children: [
        if (events.isNotEmpty) ...[
          Text(fmtSl(events.first['starts_at'] as String), style: th.textTheme.titleMedium),
          if (events.first['venue'] != null) Text(events.first['venue'] as String, style: th.textTheme.bodyMedium),
          const SizedBox(height: 12),
        ],
        // Easy Mode: one clear next step.
        Card(
          color: th.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.t('nextStep'), style: th.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(next['label'] as String, style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              if (next['key'] != 'done') ...[
                const SizedBox(height: 12),
                FilledButton(key: const Key('nextStep'), onPressed: () => onGo(next['key'] as String), child: Text(s.t('next'))),
              ],
            ]),
          ),
        ),
        if (s.isAdvanced) ReadinessCard(onGo: onGo),
        if (sum['suggestAdvanced'] == true)
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune),
              title: Text(s.t('moreControl')),
              subtitle: Text(s.t('moreControlSub')),
              trailing: TextButton(
                onPressed: () => guard(context, () async => s.setSummary(await s.api.patch('/weddings/${s.weddingId}', {'mode': 'advanced'}))),
                child: Text(s.t('switch')),
              ),
            ),
          ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.9,
          children: [
            StatTile(s.t('guests'), c['guests']),
            StatTile(s.t('sent'), c['sent']),
            StatTile(s.t('opened'), c['opened']),
            StatTile(s.t('rsvps'), c['replied']),
          ],
        ),
        if (!s.isPaid) ...[
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(s.t('upgrade')),
              subtitle: Text(s.t('upgradeSub')),
              onTap: () => onGo('upgrade'),
            ),
          ),
        ],
      ]),
    );
  }
}

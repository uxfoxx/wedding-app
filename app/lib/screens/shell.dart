import 'package:flutter/material.dart';

import '../ui.dart';
import 'admin.dart';
import 'guests_tab.dart';
import 'home_tab.dart';
import 'invitation_tab.dart';
import 'onboarding.dart';
import 'planner_home.dart';
import 'plan_tab.dart';
import 'rsvps_tab.dart';
import 'send_queue.dart';
import 'settings.dart';
import 'upgrade.dart';

/// Bottom tabs on phones, a side rail in the web panel. The first four tabs never move;
/// Advanced Mode adds Plan.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;

  void go(String key) {
    final s0 = AppScope.read(context);
    switch (key) {
      case 'invitation':
      case 'choose_template':
      case 'publish':
        setState(() => index = 1);
      case 'guests':
      case 'add_guests':
        setState(() => index = 2);
      case 'send':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SendQueueScreen(kind: 'invite')));
      case 'follow_up':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SendQueueScreen(kind: 'reminder')));
      case 'rsvps':
        setState(() => index = 3);
      case 'seating':
      case 'run_sheet':
      case 'checklist':
        setState(() => index = s0.isAdvanced ? 4 : index);
        if (!s0.isAdvanced) Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Plan')), body: const PlanTab())));
      case 'add_event':
      case 'plan':
        final s = AppScope.read(context);
        if (s.isAdvanced) {
          setState(() => index = 4);
        } else {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text(s.t('events'))), body: const PlanTab())));
        }
      case 'upgrade':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UpgradeScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final w = s.wedding;
    final tabs = <(String, IconData, Widget)>[
      (s.t('home'), Icons.home_outlined, HomeTab(onGo: go)),
      (s.t('invitation'), Icons.mail_outline, InvitationTab(onGo: go)),
      (s.t('guests'), Icons.people_outline, GuestsTab(onGo: go)),
      (s.t('rsvps'), Icons.fact_check_outlined, RsvpsTab(onGo: go)),
      if (s.isAdvanced) (s.t('plan'), Icons.event_note_outlined, const PlanTab()),
    ];
    if (index >= tabs.length) index = 0;
    final wide = isWide(context);
    final body = IndexedStack(index: index, children: [for (final t in tabs) t.$3]);

    return Scaffold(
      appBar: AppBar(
        leading: s.inPlannerWorkspace ? IconButton(tooltip: 'All client weddings', icon: const Icon(Icons.arrow_back), onPressed: s.closeWedding) : null,
        title: s.inPlannerWorkspace ? Text('${w['partner1']} & ${w['partner2']}', overflow: TextOverflow.ellipsis) : PopupMenuButton<String>(
          tooltip: 'Switch wedding',
          onSelected: (id) {
            if (id == 'new') {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingScreen(canCancel: true)));
            } else {
              guard(context, () => s.openWedding(id));
            }
          },
          itemBuilder: (_) => [
            for (final x in s.weddings) PopupMenuItem(value: x['id'] as String, child: Text('${x['partner1']} & ${x['partner2']}')),
            const PopupMenuItem(value: 'new', child: Text('+ New event')),
          ],
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text('${w['partner1']} & ${w['partner2']}', overflow: TextOverflow.ellipsis)),
            const Icon(Icons.arrow_drop_down),
          ]),
        ),
        actions: [
          if (!s.isPaid) TextButton(onPressed: () => go('upgrade'), child: Text(s.t('pass'))),
          const WorkspaceMenu(),
          if (s.isStaff)
            IconButton(tooltip: s.t('admin'), icon: const Icon(Icons.admin_panel_settings_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminScreen()))),
          IconButton(tooltip: s.t('settings'), icon: const Icon(Icons.settings_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        ],
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: index,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (i) => setState(() => index = i),
                destinations: [for (final t in tabs) NavigationRailDestination(icon: Icon(t.$2), label: Text(t.$1))],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ])
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => setState(() => index = i),
              destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.$2), label: t.$1)],
            ),
    );
  }
}

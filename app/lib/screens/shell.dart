import 'package:flutter/material.dart';

import '../ui.dart';
import 'admin.dart';
import 'guests_tab.dart';
import 'home_tab.dart';
import 'invitation_tab.dart';
import 'marketplace.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = AppScope.read(context);
      final vendor = s.deepLink.remove('vendor');
      final review = s.deepLink.remove('review');
      if (vendor != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => VendorProfileScreen(slug: vendor)));
      if (review != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Your vendors')), body: const ContactedVendors())));
    });
  }

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
      (s.t('home'), Icons.space_dashboard_outlined, HomeTab(onGo: go)),
      (s.t('invitation'), Icons.local_post_office_outlined, InvitationTab(onGo: go)),
      (s.t('guests'), Icons.groups_2_outlined, GuestsTab(onGo: go)),
      (s.t('rsvps'), Icons.how_to_reg_outlined, RsvpsTab(onGo: go)),
      if (s.isAdvanced) (s.t('plan'), Icons.auto_stories_outlined, const PlanTab()),
    ];
    if (index >= tabs.length) index = 0;
    final wide = isWide(context);
    final stack = IndexedStack(index: index, children: [for (final t in tabs) t.$3]);
    final body = s.offline
        ? Column(children: [OfflineBanner(at: s.offlineCopyAt!, onRetry: () => guard(context, s.retryOnline)), Expanded(child: stack)])
        : stack;
    final names = '${w['partner1']} & ${w['partner2']}';
    final initials = '${(w['partner1'] as String? ?? '?').characters.first}${(w['partner2'] as String? ?? '?').characters.first}';
    final heading = Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: Brand.ink, shape: BoxShape.circle),
        child: Text(initials.toUpperCase(), style: const TextStyle(fontFamily: Brand.serif, color: Brand.paper, fontSize: 15, height: 1)),
      ),
      const SizedBox(width: 10),
      Flexible(child: Text(names, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: Brand.sans, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2))),
    ]);

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: s.inPlannerWorkspace ? 0 : 16,
        leading: s.inPlannerWorkspace ? IconButton(tooltip: 'All client weddings', icon: const Icon(Icons.arrow_back_rounded), onPressed: s.closeWedding) : null,
        title: s.inPlannerWorkspace ? heading : PopupMenuButton<String>(
          tooltip: 'Switch wedding',
          position: PopupMenuPosition.under,
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
            Flexible(child: heading),
            const SizedBox(width: 2),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: Brand.ink2),
          ]),
        ),
        actions: [
          if (!s.isPaid)
            IconButton(
              tooltip: s.t('pass'),
              onPressed: () => go('upgrade'),
              style: IconButton.styleFrom(backgroundColor: Brand.accentSoft, foregroundColor: Brand.accent),
              icon: const Icon(Icons.auto_awesome_rounded, size: 20),
            ),
          const WorkspaceMenu(),
          if (s.isStaff)
            IconButton(tooltip: s.t('admin'), icon: const Icon(Icons.shield_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminScreen()))),
          IconButton(tooltip: s.t('settings'), icon: const Icon(Icons.tune_rounded), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
          const SizedBox(width: 6),
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
      bottomNavigationBar: wide ? null : DockNav(items: [for (final t in tabs) (t.$1, t.$2)], index: index, onTap: (i) => setState(() => index = i)),
    );
  }
}

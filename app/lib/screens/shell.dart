import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ui.dart';
import 'admin.dart';
import 'guests_tab.dart';
import 'home_tab.dart';
import 'invitation_tab.dart';
import 'marketplace.dart';
import 'onboarding.dart';
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
        if (!s0.isAdvanced) Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Scaffold(body: PlanTab())));
      case 'add_event':
      case 'plan':
        final s = AppScope.read(context);
        if (s.isAdvanced) {
          setState(() => index = 4);
        } else {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Scaffold(body: PlanTab())));
        }
      case 'upgrade':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UpgradeScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final tabs = <(String, IconData, Widget)>[
      (s.t('home'), CupertinoIcons.house_fill, HomeTab(onGo: go)),
      (s.t('invitation'), CupertinoIcons.envelope_open_fill, InvitationTab(onGo: go)),
      (s.t('guests'), CupertinoIcons.person_2_fill, GuestsTab(onGo: go)),
      (s.t('rsvps'), CupertinoIcons.checkmark_seal_fill, RsvpsTab(onGo: go)),
      if (s.isAdvanced) (s.t('plan'), CupertinoIcons.square_grid_2x2_fill, const PlanTab()),
    ];
    if (index >= tabs.length) index = 0;
    final wide = isWide(context);
    final stack = IndexedStack(index: index, children: [for (final t in tabs) t.$3]);
    final body = ShellChrome(
      leading: s.inPlannerWorkspace
          ? CupertinoButton(padding: EdgeInsets.zero, onPressed: s.closeWedding, child: const Icon(CupertinoIcons.chevron_back, semanticLabel: 'All client weddings'))
          : null,
      trailing: AccountButton(onGo: go),
      child: s.offline
          ? Column(children: [SafeArea(bottom: false, child: OfflineBanner(at: s.offlineCopyAt!, onRetry: () => guard(context, s.retryOnline))), Expanded(child: stack)])
          : stack,
    );

    return Scaffold(
      extendBody: true,
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: index,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (i) => setState(() => index = i),
                destinations: [for (final t in tabs) NavigationRailDestination(icon: Icon(t.$2), label: Text(t.$1))],
              ),
              const VerticalDivider(width: 0.5),
              Expanded(child: body),
            ])
          : body,
      bottomNavigationBar: wide ? null : DockNav(items: [for (final t in tabs) (t.$1, t.$2)], index: index, onTap: (i) => setState(() => index = i)),
    );
  }
}

/// The couple's monogram in the navigation bar. It opens a sheet to switch wedding or role,
/// start a new event, see the Wedding Pass, open the admin console or settings.
class AccountButton extends StatelessWidget {
  const AccountButton({super.key, required this.onGo, this.light = false});
  final void Function(String key) onGo;
  final bool light;

  Future<void> open(BuildContext context) async {
    final s = AppScope.read(context);
    final nav = Navigator.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!s.inPlannerWorkspace)
              RowGroup(header: s.t('switchWedding'), children: [
                for (final x in s.weddings)
                  ActionRow(
                    icon: CupertinoIcons.heart_fill,
                    tint: Brand.accent,
                    title: '${x['partner1']} & ${x['partner2']}',
                    trailing: x['id'] == s.weddingId ? const Icon(CupertinoIcons.checkmark_alt, color: Brand.accent) : const SizedBox.shrink(),
                    onTap: () => Navigator.pop(c, 'w:${x['id']}'),
                  ),
                ActionRow(icon: CupertinoIcons.add, tint: Brand.blue, title: s.t('newEvent'), onTap: () => Navigator.pop(c, 'new')),
              ]),
            RowGroup(header: s.t('account'), children: [
              if (!s.isPaid) ActionRow(icon: CupertinoIcons.sparkles, tint: Brand.orange, title: s.t('pass'), subtitle: s.t('upgradeSub'), onTap: () => Navigator.pop(c, 'upgrade')),
              if (s.isPlanner || s.isVendor || s.isStaff)
                for (final o in [('couple', 'My wedding', CupertinoIcons.heart), if (s.isPlanner) ('planner', 'Planner', CupertinoIcons.briefcase_fill), if (s.isVendor) ('vendor', 'Vendor', CupertinoIcons.bag_fill)])
                  ActionRow(
                    icon: o.$3,
                    tint: Brand.indigo,
                    title: o.$2,
                    trailing: s.workspace == o.$1 ? const Icon(CupertinoIcons.checkmark_alt, color: Brand.accent) : const SizedBox.shrink(),
                    onTap: () => Navigator.pop(c, 'role:${o.$1}'),
                  ),
              if (s.isStaff) ActionRow(icon: CupertinoIcons.shield_lefthalf_fill, tint: Brand.gray, title: s.t('admin'), onTap: () => Navigator.pop(c, 'admin')),
              ActionRow(icon: CupertinoIcons.gear_alt_fill, tint: Brand.gray, title: s.t('settings'), onTap: () => Navigator.pop(c, 'settings')),
            ]),
          ]),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    if (picked == 'new') {
      nav.push(MaterialPageRoute(builder: (_) => const OnboardingScreen(canCancel: true)));
    } else if (picked == 'upgrade') {
      onGo('upgrade');
    } else if (picked == 'admin') {
      nav.push(MaterialPageRoute(builder: (_) => const AdminScreen()));
    } else if (picked == 'settings') {
      nav.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    } else if (picked.startsWith('w:')) {
      await guard(context, () => s.openWedding(picked.substring(2)));
    } else if (picked.startsWith('role:')) {
      await guard(context, () => s.setWorkspace(picked.substring(5)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final w = s.wedding;
    final initials = '${(w['partner1'] as String? ?? '?').characters.first}${(w['partner2'] as String? ?? '?').characters.first}'.toUpperCase();
    return Semantics(
      button: true,
      label: '${s.t('account')}: ${w['partner1']} & ${w['partner2']}',
      excludeSemantics: true,
      child: Pressable(
        scale: 0.9,
        onTap: () => open(context),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF7A9A), Brand.accent]),
            border: Border.all(color: Colors.white.withValues(alpha: light ? 0.7 : 1), width: 2),
          ),
          child: Text(initials, style: const TextStyle(fontFamily: Brand.sansDisplay, color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

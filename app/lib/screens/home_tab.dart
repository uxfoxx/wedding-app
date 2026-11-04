import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui.dart';
import 'planner_tools.dart';
import 'shell.dart';

/// Home: the wedding as a full-bleed cover (photo, or a drifting colour field) that shrinks
/// into the navigation bar, then the next step, invitation progress as activity rings, and
/// readiness.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.onGo});
  final void Function(String key) onGo;
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final scroll = ScrollController();
  bool collapsed = false;
  static const heroHeight = 470.0;

  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      final c = scroll.offset > heroHeight - 140;
      if (c != collapsed) setState(() => collapsed = c);
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final sum = s.summary!;
    final next = sum['nextStep'] as Map<String, dynamic>;
    final c = sum['counts'] as Map<String, dynamic>;
    final events = sum['events'] as List<dynamic>;
    final w = s.wedding;
    final chrome = ShellChrome.maybeOf(context);
    final onGo = widget.onGo;

    final content = <Widget>[
      // Easy Mode: one clear next step.
      _NextStep(label: next['label'] as String, done: next['key'] == 'done', onTap: () => onGo(next['key'] as String)),
      _Progress(guests: c['guests'] as int, sent: c['sent'] as int, opened: c['opened'] as int, replied: c['replied'] as int, onTap: () => onGo('rsvps')),
      if (s.isAdvanced) ReadinessCard(onGo: onGo),
      if (sum['suggestAdvanced'] == true)
        RowGroup(children: [
          ActionRow(
            icon: CupertinoIcons.slider_horizontal_3,
            tint: Brand.indigo,
            title: s.t('moreControl'),
            subtitle: s.t('moreControlSub'),
            trailing: TextButton(
              onPressed: () => guard(context, () async => s.setSummary(await s.api.patch('/weddings/${s.weddingId}', {'mode': 'advanced'}))),
              child: Text(s.t('switch')),
            ),
          ),
        ]),
      if (!s.isPaid) _PassPromo(onTap: () => onGo('upgrade')),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: collapsed ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: CustomScrollView(
        controller: scroll,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          SliverAppBar(
            pinned: true,
            stretch: true,
            onStretchTrigger: s.refresh,
            expandedHeight: heroHeight,
            backgroundColor: Brand.paper,
            surfaceTintColor: Colors.transparent,
            systemOverlayStyle: collapsed ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
            leading: chrome?.leading,
            automaticallyImplyLeading: false,
            title: AnimatedOpacity(
              opacity: collapsed ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Text('${w['partner1']} & ${w['partner2']}'),
            ),
            actions: [Padding(padding: const EdgeInsets.only(right: 14), child: AccountButton(onGo: onGo, light: !collapsed))],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              stretchModes: const [StretchMode.zoomBackground, StretchMode.blurBackground],
              background: _Hero(event: events.isEmpty ? null : events.first as Map<String, dynamic>),
            ),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < content.length; i++) Reveal(index: i + 2, child: content[i]),
                  ]),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 12)),
        ],
      ),
    );
  }
}

/// The cover: the couple's photo (or a drifting colour field), their names in the invitation
/// serif, the date and a glass countdown.
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
    final hasCover = cover != null && cover.isNotEmpty;
    final top = MediaQuery.paddingOf(context).top;

    return Stack(fit: StackFit.expand, children: [
      const MeshBackdrop(),
      if (hasCover) Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
      // Darkens the bottom so the names read on any photo.
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0, 0.35, 1],
            colors: [Colors.black.withValues(alpha: 0.35), Colors.black.withValues(alpha: hasCover ? 0.05 : 0), Colors.black.withValues(alpha: hasCover ? 0.72 : 0.45)],
          ),
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(22, top + 56, 22, 26),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Spacer(),
          Reveal(index: 0, child: Eyebrow(s.t(w['kind'] as String? ?? 'wedding'), color: Colors.white.withValues(alpha: 0.85))),
          const SizedBox(height: 10),
          Reveal(index: 1, offset: 0.12, child: CoupleNames('${w['partner1']}', '${w['partner2']}', size: 56, color: Colors.white, amp: const Color(0xFFFFC2D1))),
          const SizedBox(height: 18),
          Reveal(
            index: 2,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: at == null
                    ? const SizedBox()
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${_days[at.weekday - 1]}, ${at.day} ${_months[at.month - 1]} ${at.year}', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(
                          [
                            '$h:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'am' : 'pm'}',
                            if (event!['venue'] != null && '${event!['venue']}'.isNotEmpty) '${event!['venue']}',
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 15),
                        ),
                      ]),
              ),
              if (days != null && days >= 0) ...[
                const SizedBox(width: 12),
                Semantics(
                  label: days == 0 ? s.t('today') : '$days ${s.t('daysToGo')}',
                  excludeSemantics: true,
                  child: Glass(
                    dark: true,
                    radius: 22,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Column(children: [
                      days == 0
                          ? const Icon(CupertinoIcons.heart_fill, color: Colors.white, size: 34)
                          : AnimatedCount(days, style: Brand.display(38, color: Colors.white)),
                      Text(days == 0 ? s.t('today') : s.t('daysToGo'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ],
            ]),
          ),
        ]),
      ),
    ]);
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
      onTap: done ? null : onTap,
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF6A8D), Brand.accent, Color(0xFFB21E5B)]),
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(CupertinoIcons.sparkles, color: Colors.white, size: 15),
              const SizedBox(width: 6),
              Text(s.t('nextStep'), style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            Text(label, style: Brand.display(24, color: Colors.white)),
          ]),
        ),
        if (!done) ...[
          const SizedBox(width: 12),
          Semantics(
            button: true,
            label: s.t('next'),
            child: GestureDetector(
              key: const Key('nextStep'),
              onTap: onTap,
              child: Container(
                width: 50,
                height: 50,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(CupertinoIcons.arrow_right, color: Brand.accent),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// How far the invitations have got, as activity rings: sent, opened and replied, each out of
/// the guest list.
class _Progress extends StatelessWidget {
  const _Progress({required this.guests, required this.sent, required this.opened, required this.replied, required this.onTap});
  final int guests, sent, opened, replied;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    double f(int n) => guests == 0 ? 0 : n / guests;
    Widget legend(String label, int n, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Semantics(
            label: '$label: $n of $guests',
            excludeSemantics: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                AnimatedCount(n, style: Brand.display(24, color: Colors.white)),
                Text('/$guests', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 15, fontWeight: FontWeight.w600)),
              ]),
            ]),
          ),
        );
    return Panel(
      onTap: onTap,
      color: Brand.night,
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(s.t('guests'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          AnimatedCount(guests, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 17, fontWeight: FontWeight.w600)),
          const Spacer(),
          Icon(CupertinoIcons.chevron_forward, color: Colors.white.withValues(alpha: 0.45), size: 17),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          ActivityRings(values: [f(sent), f(opened), f(replied)], size: 138, stroke: 16),
          const SizedBox(width: 22),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              legend(s.t('sent'), sent, Brand.ringMove),
              legend(s.t('opened'), opened, Brand.ringExercise),
              legend(s.t('rsvps'), replied, Brand.ringStand),
            ]),
          ),
        ]),
      ]),
    );
  }
}

class _PassPromo extends StatelessWidget {
  const _PassPromo({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Pressable(
        onTap: onTap,
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 150),
            child: Stack(children: [
              const Positioned.fill(child: MeshBackdrop(colors: [Color(0xFF7A5CFF), Color(0xFFFF5E87), Color(0xFFFFB25E), Color(0xFF3B1F6B)], base: Color(0xFF241338))),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  const Icon(CupertinoIcons.sparkles, color: Colors.white, size: 24),
                  const SizedBox(height: 26),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.t('upgrade'), style: Brand.display(24, color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(s.t('upgradeSub'), maxLines: 2, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14)),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Glass(dark: true, radius: 99, padding: const EdgeInsets.all(10), child: const Icon(CupertinoIcons.arrow_right, color: Colors.white, size: 20)),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

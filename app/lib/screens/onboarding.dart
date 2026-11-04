import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ui.dart';

/// First run: what are you planning → Easy or Advanced → names, ceremony, date, venue.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.canCancel = false});
  final bool canCancel;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int step = 0;
  String kind = 'wedding';
  String mode = 'easy';
  String type = 'buddhist';
  final p1 = TextEditingController();
  final p2 = TextEditingController();
  final venue = TextEditingController();
  final address = TextEditingController();
  DateTime? date;
  TimeOfDay time = const TimeOfDay(hour: 10, minute: 0);
  bool busy = false;

  static const types = {'buddhist': 'Buddhist (Poruwa)', 'hindu': 'Hindu (Kovil)', 'christian': 'Christian (Church)', 'muslim': 'Muslim (Nikah)', 'civil': 'Civil registration', 'mixed': 'Mixed / other'};

  Future<void> create() async {
    final s = AppScope.read(context);
    if (p1.text.trim().isEmpty || p2.text.trim().isEmpty || date == null) {
      toast(context, 'Please add both names and the date.');
      return;
    }
    setState(() => busy = true);
    final r = await guard(context, () => s.api.post('/weddings', {
          'kind': kind, 'mode': mode, 'wedding_type': type, 'language': s.locale,
          'partner1': p1.text.trim(), 'partner2': p2.text.trim(),
          'event': {'starts_at': slToIso(date!, time), 'venue': venue.text.trim(), 'address': address.text.trim()},
          'code': ?(s.deepLink['ref'] ?? s.deepLink['code']),
          'from_slug': ?s.deepLink['from'],
        }));
    if (r != null) {
      await s.createdWedding(r);
      if (mounted && widget.canCancel) Navigator.of(context).pop();
    }
    if (mounted) setState(() => busy = false);
  }

  Widget choice(String label, String sub, IconData icon, bool selected, VoidCallback onTap) => Semantics(
        selected: selected,
        child: Panel(
          onTap: onTap,
          color: selected ? Brand.accentSoft : Brand.surface,
          borderColor: selected ? Brand.accent : null,
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            IconTile(icon, tint: selected ? Brand.accent : null),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: Brand.display(20)),
                if (sub.isNotEmpty) ...[const SizedBox(height: 4), Text(sub, style: const TextStyle(color: Brand.ink2, fontSize: 15))],
              ]),
            ),
            const SizedBox(width: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 26,
              height: 26,
              decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? Brand.accent : Colors.transparent, border: Border.all(color: selected ? Brand.accent : Brand.ink3, width: 1.5)),
              child: selected ? const Icon(CupertinoIcons.checkmark_alt, size: 16, color: Colors.white) : null,
            ),
          ]),
        ),
      );

  /// A date or time that opens a picker, drawn like a field with its label above the value.
  Widget pickerField(String label, String value, IconData icon, VoidCallback onTap, {Key? key}) => Panel(
        key: key,
        onTap: onTap,
        margin: EdgeInsets.zero,
        radius: 14,
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Eyebrow(label),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ]),
          ),
          Icon(icon, color: Brand.ink2, size: 20),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final steps = <Widget>[
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('whatPlanning'), style: Brand.display(34)),
        const SizedBox(height: 20),
        for (final k in const [('wedding', CupertinoIcons.heart_fill), ('engagement', CupertinoIcons.sparkles), ('homecoming', CupertinoIcons.house_fill), ('other', CupertinoIcons.gift_fill)])
          choice(s.t(k.$1), '', k.$2, kind == k.$1, () => setState(() { kind = k.$1; step = 1; })),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('mode'), style: Brand.display(34)),
        const SizedBox(height: 16),
        choice(s.t('startSimple'), s.t('startSimpleSub'), CupertinoIcons.bolt_fill, mode == 'easy', () => setState(() { mode = 'easy'; step = 2; })),
        choice(s.t('fullTools'), s.t('fullToolsSub'), CupertinoIcons.slider_horizontal_3, mode == 'advanced', () => setState(() { mode = 'advanced'; step = 2; })),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('names'), style: Brand.display(34)),
        const SizedBox(height: 16),
        TextField(key: const Key('p1'), controller: p1, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: s.t('partner1'))),
        const SizedBox(height: 12),
        TextField(key: const Key('p2'), controller: p2, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: s.t('partner2'))),
        const SizedBox(height: 12),
        if (kind == 'wedding')
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: InputDecoration(labelText: s.t('ceremony')),
            items: [for (final e in types.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => type = v!),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: pickerField(s.t('date'), date == null ? '—' : '${date!.day}/${date!.month}/${date!.year}', CupertinoIcons.calendar, key: const Key('date'), () async {
              final now = DateTime.now();
              final d = await showDatePicker(context: context, firstDate: now.subtract(const Duration(days: 1)), lastDate: DateTime(now.year + 4), initialDate: date ?? now.add(const Duration(days: 120)));
              if (d != null) setState(() => date = d);
            }),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: pickerField(s.t('time'), time.format(context), CupertinoIcons.clock, () async {
              final t = await showTimePicker(context: context, initialTime: time);
              if (t != null) setState(() => time = t);
            }),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(key: const Key('venue'), controller: venue, decoration: InputDecoration(labelText: s.t('venue'))),
        const SizedBox(height: 12),
        TextField(controller: address, decoration: InputDecoration(labelText: s.t('address'))),
        const SizedBox(height: 20),
        FilledButton(key: const Key('create'), onPressed: busy ? null : create, child: Text(s.t('create'))),
      ]),
    ];
    return Scaffold(
      appBar: AppBar(
        leading: step > 0
            ? IconButton(icon: const Icon(CupertinoIcons.chevron_back), tooltip: s.t('back'), onPressed: () => setState(() => step--))
            : widget.canCancel ? const CloseButton() : null,
        centerTitle: true,
        title: Column(mainAxisSize: MainAxisSize.min, children: [
          Eyebrow(s.t('stepOf', {'n': step + 1, 'total': 3})),
          const SizedBox(height: 8),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 3; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == step ? 34 : 18,
                height: 5,
                decoration: BoxDecoration(color: i <= step ? Brand.accent : Brand.line, borderRadius: BorderRadius.circular(9)),
              ),
          ]),
        ]),
        actions: [if (!widget.canCancel && step == 0) TextButton(onPressed: () => s.signOut(), child: Text(s.t('signOut')))],
      ),
      body: SafeArea(child: PageBody(maxWidth: 560, padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                child: KeyedSubtree(key: ValueKey(step), child: steps[step]),
              )])),
    );
  }
}

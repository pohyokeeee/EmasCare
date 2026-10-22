import 'package:flutter/material.dart';
import '../../app/app_shell.dart';
import '../../app/preview_controller.dart';
import '../../models/backend_models.dart';
import '../../models/community_models.dart';
import '../../shared/design_system.dart';
import 'community_ui.dart';
import 'session_ui.dart';

String minuteLabel(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
String weekdayLabel(int day, bool bm) => (bm
    ? ['Isnin', 'Selasa', 'Rabu', 'Khamis', 'Jumaat', 'Sabtu', 'Ahad']
    : [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ])[day - 1];

class LiveAvailabilityCard extends StatelessWidget {
  const LiveAvailabilityCard({super.key});
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), community = c.community;
    final helper = community?.helper;
    if (community?.catalogError != null) {
      return CommunityError(
        community!.catalogError!.message(c.malay),
        retry: community.retry,
      );
    }
    return Surface(
      color: Palette.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            c.t('Room for a little company?', 'Ada masa untuk menemani?'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Text(
            c.t(
              'Set the hours that work for you. Existing sessions stay on your schedule.',
              'Tetapkan waktu yang sesuai. Sesi sedia ada kekal dalam jadual anda.',
            ),
            style: const TextStyle(color: Palette.muted),
          ),
          const SizedBox(height: 16),
          if (community?.helperLoading == true)
            const LinearProgressIndicator()
          else if (helper == null)
            Text(
              c.t(
                'No helper profile is recorded yet.',
                'Profil pembantu belum direkodkan.',
              ),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Pill(
                  helper.available
                      ? c.t('Available', 'Tersedia')
                      : c.t('Unavailable', 'Tidak tersedia'),
                  icon: Icons.schedule,
                ),
                Pill(
                  helper.approved
                      ? c.t('Approved helper', 'Pembantu diluluskan')
                      : c.t('Approval pending', 'Menunggu kelulusan'),
                ),
                Pill(helper.languages.map((s) => s.toUpperCase()).join(' / ')),
              ],
            ),
            const SizedBox(height: 16),
            if (helper.slots.isEmpty)
              Text(
                c.t('No weekly hours saved.', 'Tiada waktu mingguan disimpan.'),
              )
            else
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(c.t('View weekly hours', 'Lihat waktu mingguan')),
                children: [
                  for (final s in helper.slots)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${weekdayLabel(s['weekday'] as int, c.malay)} · ${minuteLabel(s['startMinute'] as int)}–${minuteLabel(s['endMinute'] as int)} MYT',
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            EmasButton(
              label: c.t('Edit availability', 'Edit ketersediaan'),
              secondary: true,
              icon: Icons.edit_calendar_outlined,
              onPressed: () => showEmasSheet(
                context,
                CommunitySheetGuard(
                  token: scopeToken(c),
                  child: _AvailabilityEditor(helper),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SlotInput {
  _SlotInput(this.day, int start, int end)
    : start = TextEditingController(text: minuteLabel(start)),
      end = TextEditingController(text: minuteLabel(end));
  int day;
  final TextEditingController start, end;
  void dispose() {
    start.dispose();
    end.dispose();
  }
}

class _AvailabilityEditor extends StatefulWidget {
  const _AvailabilityEditor(this.helper);
  final HelperProfileRecord helper;
  @override
  State<_AvailabilityEditor> createState() => _AvailabilityEditorState();
}

class _AvailabilityEditorState extends State<_AvailabilityEditor> {
  late bool _available = widget.helper.available;
  late final List<_SlotInput> _slots = [
    for (final s in widget.helper.slots)
      _SlotInput(
        s['weekday'] as int,
        s['startMinute'] as int,
        s['endMinute'] as int,
      ),
  ];
  final List<_SlotInput> _removed = [];
  String? _intent, _validation;
  int? _minute(String text, {bool end = false}) {
    if (end && text == '24:00') return 1440;
    if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(text)) return null;
    final pieces = text.split(':').map(int.parse).toList();
    return pieces[0] * 60 + pieces[1];
  }

  void _done() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    sessionToast(context, 'Availability saved.', 'Ketersediaan disimpan.');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.sessions!;
    _intent ??= w.nextIntent();
    final name = 'availability:$_intent';
    final pending = w.actions[name] != null;
    if (w.error != null) {
      return CommunityError(w.error!.message(c.malay), retry: w.retry);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          c.t('Make time for good company.', 'Luangkan masa untuk menemani.'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(
          c.t(
            'Weekly hours follow Malaysia time. Use 24:00 for the end of a full day. Empty hours mean no new assignments.',
            'Waktu mingguan mengikut masa Malaysia. Gunakan 24:00 untuk penghujung hari. Waktu kosong bermaksud tiada penugasan baharu.',
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(c.t('Available to help', 'Sedia membantu')),
          value: _available,
          onChanged: pending ? null : (v) => setState(() => _available = v),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _slots.length; i++) ...[
          Surface(
            color: Palette.canvas,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ObjectKey(_slots[i]),
                        initialValue: _slots[i].day,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: c.t('Day', 'Hari'),
                        ),
                        items: [
                          for (var d = 1; d <= 7; d++)
                            DropdownMenuItem(
                              value: d,
                              child: Text(weekdayLabel(d, c.malay)),
                            ),
                        ],
                        onChanged: pending
                            ? null
                            : (v) => setState(() => _slots[i].day = v!),
                      ),
                    ),
                    IconButton(
                      tooltip: c.t(
                        'Remove interval ${i + 1}',
                        'Buang selang ${i + 1}',
                      ),
                      onPressed: pending
                          ? null
                          : () => setState(
                              () => _removed.add(_slots.removeAt(i)),
                            ),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _slots[i].start,
                        enabled: !pending,
                        decoration: InputDecoration(
                          labelText: c.t('From · HH:mm', 'Dari · HH:mm'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _slots[i].end,
                        enabled: !pending,
                        decoration: InputDecoration(
                          labelText: c.t('Until · HH:mm', 'Hingga · HH:mm'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextButton.icon(
          onPressed: pending
              ? null
              : () => setState(() => _slots.add(_SlotInput(1, 540, 720))),
          icon: const Icon(Icons.add),
          label: Text(c.t('Add weekly interval', 'Tambah selang mingguan')),
        ),
        if (_validation != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _validation!,
              style: const TextStyle(color: Palette.gold),
            ),
          ),
        const SizedBox(height: 18),
        EmasButton(
          key: const ValueKey('save-live-availability'),
          label: c.t('Save availability', 'Simpan ketersediaan'),
          onPressed: pending
              ? null
              : () async {
                  final slots = <Json>[];
                  for (final s in _slots) {
                    final start = _minute(s.start.text),
                        end = _minute(s.end.text, end: true);
                    if (start == null || end == null || start >= end) {
                      setState(
                        () => _validation = c.t(
                          'Check each interval: use HH:mm and an end after the start.',
                          'Semak setiap selang: gunakan HH:mm dan masa tamat selepas mula.',
                        ),
                      );
                      return;
                    }
                    slots.add({
                      'weekday': s.day,
                      'startMinute': start,
                      'endMinute': end,
                    });
                  }
                  slots.sort(
                    (a, b) =>
                        (a['weekday'] as int).compareTo(b['weekday'] as int) !=
                            0
                        ? (a['weekday'] as int).compareTo(b['weekday'] as int)
                        : (a['startMinute'] as int).compareTo(
                            b['startMinute'] as int,
                          ),
                  );
                  for (var i = 1; i < slots.length; i++) {
                    if (slots[i]['weekday'] == slots[i - 1]['weekday'] &&
                        (slots[i]['startMinute'] as int) <
                            (slots[i - 1]['endMinute'] as int)) {
                      setState(
                        () => _validation = c.t(
                          'Weekly intervals cannot overlap.',
                          'Selang mingguan tidak boleh bertindih.',
                        ),
                      );
                      return;
                    }
                  }
                  setState(() => _validation = null);
                  final saved = await w.run(name, 'availability', {
                    'available': _available,
                    'slots': slots,
                  });
                  if (mounted && saved) _done();
                },
        ),
        PendingSessionAction(name, onSuccess: _done),
      ],
    );
  }

  @override
  void dispose() {
    for (final s in [..._slots, ..._removed]) {
      s.dispose();
    }
    super.dispose();
  }
}

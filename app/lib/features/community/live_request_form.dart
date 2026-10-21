import 'package:flutter/material.dart';
import '../../app/preview_controller.dart';
import '../../models/backend_models.dart';
import '../../models/community_models.dart';
import '../../models/preview_models.dart';
import '../../shared/design_system.dart';
import 'community_ui.dart';
import 'session_ui.dart';

class LiveRequestForm extends StatefulWidget {
  const LiveRequestForm({super.key, this.activity, this.onBack});
  final ActivityRecord? activity;
  final VoidCallback? onBack;
  @override
  State<LiveRequestForm> createState() => _LiveRequestFormState();
}

class _LiveRequestFormState extends State<LiveRequestForm> {
  final _form = GlobalKey<FormState>();
  final _date = TextEditingController(),
      _time = TextEditingController(),
      _minutes = TextEditingController(text: '60');
  String _task = 'walk_with_me',
      _language = 'en',
      _gender = 'any',
      _intent = '';
  String? _placeId;
  Json? _review;
  String? _validation;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intent.isNotEmpty) return;
    final c = PreviewScope.of(context);
    _intent = c.sessions!.nextIntent();
    _language = c.malay ? 'bm' : 'en';
    final at =
        widget.activity?.startsAt ??
        DateTime.parse(
          '${malaysiaDate(c.sessions!.now.add(const Duration(days: 1)))}T10:00:00+08:00',
        );
    _date.text = malaysiaDate(at);
    _time.text = malaysiaTime(at);
    _placeId = widget.activity?.placeId;
  }

  String get _action => 'create:$_intent';
  void _prepare(PreviewController c) {
    if (!_form.currentState!.validate()) return;
    final a = widget.activity;
    final start =
        a?.startsAt ??
        DateTime.tryParse('${_date.text}T${_time.text}:00+08:00');
    final minutes = int.tryParse(_minutes.text);
    final end =
        a?.endsAt ??
        (start == null || minutes == null
            ? null
            : start.add(Duration(minutes: minutes)));
    if (start == null ||
        end == null ||
        !start.isAfter(c.sessions!.now) ||
        !end.isAfter(start) ||
        end.difference(start).inMinutes > 1440 ||
        (a == null &&
            (malaysiaDate(start) != _date.text ||
                malaysiaTime(start) != _time.text))) {
      setState(
        () => _validation = c.t(
          'Choose a valid future date, time and duration.',
          'Pilih tarikh, masa dan tempoh akan datang yang sah.',
        ),
      );
      return;
    }
    if (_task != 'phone_help' &&
        !(c.community?.places.any((p) => p.id == _placeId) ?? false)) {
      setState(
        () => _validation = c.t(
          'Choose a recorded meeting place.',
          'Pilih tempat pertemuan yang direkodkan.',
        ),
      );
      return;
    }
    setState(() {
      _validation = null;
      _review = Map.unmodifiable({
        'elderId': c.role == AppRole.elder
            ? c.session!.profile!.uid
            : c.session!.selectedElderId,
        'activityId': a?.id,
        'placeId': _task == 'phone_help' ? null : _placeId,
        'startsAt': start.toUtc().toIso8601String(),
        'endsAt': end.toUtc().toIso8601String(),
        'taskType': _task,
        'preferredLanguage': _language,
        'preferredHelperGender': _gender,
      });
    });
  }

  void _done(PreviewController c) {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    sessionToast(
      context,
      'Request sent. Your coordinator can arrange a companion.',
      'Permintaan dihantar. Penyelaras boleh mengatur teman.',
    );
    Navigator.of(context).pop();
    c.navigate(destination: Destination.companion);
  }

  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.sessions!;
    final family = c.role == AppRole.family;
    if ((family && c.session!.selectedElder?.booking != true) ||
        (!family && c.role != AppRole.elder)) {
      return CommunityError(
        c.t(
          'Booking needs your elder’s consent.',
          'Tempahan memerlukan kebenaran warga emas.',
        ),
      );
    }
    if (w.error != null) {
      return CommunityError(w.error!.message(c.malay), retry: w.retry);
    }
    if (c.community?.catalogError != null) {
      return CommunityError(
        c.community!.catalogError!.message(c.malay),
        retry: c.community!.retry,
      );
    }
    final pending = w.actions[_action] != null;
    final elder = family
        ? c.session!.selectedElder!.displayName
        : c.session!.profile!.displayName;
    if (_review != null) {
      final r = _review!;
      final place = c.community?.places
          .where((p) => p.id == r['placeId'])
          .firstOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text(c.t('Edit request', 'Edit permintaan')),
              onPressed: pending ? null : () => setState(() => _review = null),
            ),
          ),
          Text(
            c.t('Does this look right?', 'Adakah semuanya betul?'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Pill(
              c.t('Ready to send', 'Sedia dihantar'),
              icon: Icons.outgoing_mail,
            ),
          ),
          const SizedBox(height: 20),
          Surface(
            color: Palette.canvas,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (label, value) in [
                  (c.t('For', 'Untuk'), elder),
                  (
                    c.t('Activity / help', 'Aktiviti / bantuan'),
                    widget.activity?.title.inLanguage(c.malay) ??
                        sessionTask(_task, c.malay),
                  ),
                  (
                    c.t('Companion task', 'Tugas teman'),
                    sessionTask(_task, c.malay),
                  ),
                  (
                    c.t('When', 'Bila'),
                    sessionWhen(
                      DateTime.parse(r['startsAt']),
                      DateTime.parse(r['endsAt']),
                      c.malay,
                    ),
                  ),
                  (
                    c.t('Meeting place', 'Tempat pertemuan'),
                    _task == 'phone_help'
                        ? c.t('By phone', 'Melalui telefon')
                        : place?.name ?? '',
                  ),
                  (
                    c.t('Language', 'Bahasa'),
                    _language == 'bm' ? 'Bahasa Melayu' : 'English',
                  ),
                  (
                    c.t('Companion preference', 'Pilihan teman'),
                    genderLabel(_gender, c.malay),
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          value,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            c.t(
              'Your coordinator will arrange the companion. Sending a request does not confirm an assignment.',
              'Penyelaras akan mengatur teman. Menghantar permintaan belum mengesahkan penugasan.',
            ),
          ),
          const SizedBox(height: 18),
          EmasButton(
            key: const ValueKey('send-live-request'),
            label: c.t('Send request', 'Hantar permintaan'),
            icon: Icons.arrow_forward,
            onPressed: pending
                ? null
                : () async {
                    final saved = await w.run(_action, 'create', r);
                    if (mounted && saved) _done(c);
                  },
          ),
          PendingSessionAction(_action, onSuccess: () => _done(c)),
        ],
      );
    }
    final places = c.community?.places ?? <PlaceRecord>[];
    final a = widget.activity;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: Text(c.t('Activity details', 'Butiran aktiviti')),
              ),
            ),
          Text(
            c.t('A little company, arranged.', 'Sedikit teman, dirancang.'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Text(
            c.t(
              'Choose what would help. You’ll review the plan before sending it.',
              'Pilih bantuan yang diperlukan. Semak rancangan sebelum menghantarnya.',
            ),
            style: const TextStyle(color: Palette.muted),
          ),
          const SizedBox(height: 22),
          Pill(c.t('For $elder', 'Untuk $elder'), icon: Icons.person_outline),
          if (a != null) ...[
            const SizedBox(height: 20),
            Surface(
              color: Palette.soft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.title.inLanguage(c.malay),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${activityDate(a.startsAt, c.malay)} · ${malaysiaTime(a.startsAt)}–${malaysiaTime(a.endsAt)} MYT',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    c.t(
                      'This request follows the full activity schedule.',
                      'Permintaan ini mengikut jadual penuh aktiviti.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          Text(
            c.t('What would help?', 'Bantuan yang diperlukan?'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final task in [
                'walk_with_me',
                'sit_with_me',
                if (a == null) 'phone_help',
                'carry_light_item',
              ])
                ChoiceChip(
                  label: Text(sessionTask(task, c.malay)),
                  selected: _task == task,
                  onSelected: (_) => setState(() => _task = task),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (a == null) ...[
            TextFormField(
              controller: _date,
              decoration: InputDecoration(
                labelText: c.t(
                  'Date · YYYY-MM-DD (Malaysia)',
                  'Tarikh · YYYY-MM-DD (Malaysia)',
                ),
              ),
              validator: (v) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v ?? '')
                  ? null
                  : c.t('Use YYYY-MM-DD.', 'Gunakan YYYY-MM-DD.'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _time,
              decoration: InputDecoration(
                labelText: c.t(
                  'Start time · HH:mm (MYT)',
                  'Masa mula · HH:mm (MYT)',
                ),
              ),
              validator: (v) =>
                  RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v ?? '')
                  ? null
                  : c.t('Use a 24-hour time.', 'Gunakan masa 24 jam.'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: c.t(
                  'Minutes together (1–1440)',
                  'Tempoh bersama dalam minit (1–1440)',
                ),
              ),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return n != null && n >= 1 && n <= 1440
                    ? null
                    : c.t('Enter 1–1440 minutes.', 'Masukkan 1–1440 minit.');
              },
            ),
            const SizedBox(height: 16),
          ],
          if (_task != 'phone_help')
            DropdownButtonFormField<String>(
              key: ValueKey('place-$_task-${places.map((p) => p.id).join()}'),
              isExpanded: true,
              initialValue: places.any((p) => p.id == _placeId)
                  ? _placeId
                  : null,
              decoration: InputDecoration(
                labelText: c.t('Meeting place', 'Tempat pertemuan'),
              ),
              items: [
                for (final p in places)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: a != null ? null : (v) => setState(() => _placeId = v),
              validator: (v) => v == null
                  ? c.t(
                      'Choose a recorded place.',
                      'Pilih tempat yang direkodkan.',
                    )
                  : null,
            )
          else
            Text(
              c.t(
                'Phone help has no meeting place or activity.',
                'Bantuan telefon tidak mempunyai tempat pertemuan atau aktiviti.',
              ),
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _language,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: c.t('Preferred language', 'Bahasa pilihan'),
            ),
            items: const [
              DropdownMenuItem(value: 'en', child: Text('English')),
              DropdownMenuItem(value: 'bm', child: Text('Bahasa Melayu')),
            ],
            onChanged: (v) => setState(() => _language = v!),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _gender,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: c.t('Companion preference', 'Pilihan teman'),
            ),
            items: [
              for (final g in ['any', 'female', 'male'])
                DropdownMenuItem(
                  value: g,
                  child: Text(genderLabel(g, c.malay)),
                ),
            ],
            onChanged: (v) => setState(() => _gender = v!),
          ),
          if (_validation != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _validation!,
                  style: const TextStyle(color: Palette.gold),
                ),
              ),
            ),
          const SizedBox(height: 24),
          EmasButton(
            key: const ValueKey('review-request'),
            label: c.t('Review request', 'Semak permintaan'),
            icon: Icons.arrow_forward,
            onPressed: c.community?.catalogLoading == true
                ? null
                : () => _prepare(c),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _date.dispose();
    _time.dispose();
    _minutes.dispose();
    super.dispose();
  }
}

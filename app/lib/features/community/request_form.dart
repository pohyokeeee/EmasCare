import 'package:flutter/material.dart';
import '../../app/app_shell.dart';
import '../../app/preview_controller.dart';
import '../../models/backend_models.dart';
import '../../models/community_models.dart';
import '../../models/companion_ui_models.dart';
import '../../models/preview_models.dart';
import '../../shared/design_system.dart';
import 'community_ui.dart';
import 'live_request_form.dart';

void openCompanionRequest(BuildContext context) {
  final c = PreviewScope.of(context);
  showEmasSheet(
    context,
    CommunitySheetGuard(
      token: scopeToken(c),
      child: const CompanionRequestForm(),
    ),
  );
}

class CompanionRequestForm extends StatefulWidget {
  const CompanionRequestForm({
    super.key,
    this.activity,
    this.place,
    this.onBack,
  });
  final ActivityRecord? activity;
  final PlaceRecord? place;
  final VoidCallback? onBack;
  @override
  State<CompanionRequestForm> createState() => _CompanionRequestFormState();
}

class _CompanionRequestFormState extends State<CompanionRequestForm> {
  final _form = GlobalKey<FormState>();
  final _date = TextEditingController(),
      _time = TextEditingController(),
      _place = TextEditingController(),
      _note = TextEditingController();
  CompanionTask _task = CompanionTask.walkWithMe;
  String _language = 'en', _intent = '';
  int _minutes = 60;
  bool _initialized = false;
  CompanionDraft? _review;
  String? _error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final c = PreviewScope.of(context);
    final date =
        widget.activity?.startsAt ??
        DateTime.parse(
          '${malaysiaDate((c.session?.clock() ?? DateTime.now()).add(const Duration(days: 1)))}T10:00:00+08:00',
        );
    _date.text = malaysiaDate(date);
    _time.text = malaysiaTime(date);
    _place.text = widget.place?.name ?? '';
    _language = c.malay ? 'bm' : 'en';
    _intent = c.demo.nextIntent();
  }

  @override
  void dispose() {
    _date.dispose();
    _time.dispose();
    _place.dispose();
    _note.dispose();
    super.dispose();
  }

  bool _permitted(PreviewController c) {
    return c.role == AppRole.elder;
  }

  String _elderName(PreviewController c) => c.session?.connected == true
      ? c.role == AppRole.elder
            ? c.session!.profile!.displayName
            : c.session!.selectedElder!.displayName
      : 'Mr Tan';
  void _prepare(PreviewController c) {
    if (!_permitted(c) || !_form.currentState!.validate()) return;
    final at = DateTime.tryParse('${_date.text}T${_time.text}:00+08:00');
    final now = c.session?.clock() ?? DateTime.now();
    if (at == null || malaysiaDate(at) != _date.text || !at.isAfter(now)) {
      setState(
        () => _error = c.t(
          'Choose a valid future date and time.',
          'Pilih tarikh dan masa akan datang yang sah.',
        ),
      );
      return;
    }
    setState(() {
      _error = null;
      _review = CompanionDraft(
        intentId: _intent,
        elderName: _elderName(c),
        title:
            widget.activity?.title.inLanguage(c.malay) ??
            taskName(_task, c.malay),
        activityId: widget.activity?.id,
        task: _task,
        startsAt: at.toUtc(),
        minutes: _minutes,
        language: _language,
        placeName: _place.text.trim(),
        note: _note.text.trim(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    final live = c.session?.connected == true;
    if (live && c.sessions != null) {
      return LiveRequestForm(activity: widget.activity, onBack: widget.onBack);
    }
    if (!_permitted(c)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconTile(Icons.lock_outline),
          const SizedBox(height: 18),
          Text(
            c.t(
              'Only the elder can request a companion.',
              'Hanya warga emas boleh meminta teman.',
            ),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            c.t(
              'Family, helpers and coordinators can view the parts permitted to them, but the elder starts every companion request.',
              'Keluarga, pembantu dan penyelaras boleh melihat bahagian yang dibenarkan, tetapi warga emas memulakan setiap permintaan teman.',
            ),
          ),
          const SizedBox(height: 18),
          EmasButton(
            label: c.t('Go back', 'Kembali'),
            secondary: true,
            onPressed: widget.onBack ?? () => Navigator.pop(context),
          ),
        ],
      );
    }
    if (_review != null) return _reviewPage(c, _review!, live);
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
              'Tell us what would make the day easier. You’ll review everything before the next step.',
              'Nyatakan bantuan yang memudahkan hari anda. Semak semuanya sebelum langkah seterusnya.',
            ),
            style: const TextStyle(color: Palette.muted),
          ),
          const SizedBox(height: 20),
          if (!live)
            const SampleJourneyBanner()
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Pill(
                c.t(
                  'Draft only · no booking will be sent',
                  'Draf sahaja · tiada tempahan dihantar',
                ),
                gold: true,
                icon: Icons.edit_note,
              ),
            ),
          Text(
            c.t('FOR ${_elderName(c)}', 'UNTUK ${_elderName(c)}'),
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: .9,
              fontWeight: FontWeight.w600,
              color: Palette.muted,
            ),
          ),
          if (widget.activity != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                widget.activity!.title.inLanguage(c.malay),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          const SizedBox(height: 22),
          Text(
            c.t('What would help?', 'Bantuan yang diperlukan?'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 7,
            children: [
              for (final task in CompanionTask.values.where(
                (t) => widget.activity == null || t != CompanionTask.phoneHelp,
              ))
                ChoiceChip(
                  key: ValueKey('task-${task.name}'),
                  label: Text(taskName(task, c.malay)),
                  selected: task == _task,
                  onSelected: (_) => setState(() => _task = task),
                ),
            ],
          ),
          const SizedBox(height: 22),
          TextFormField(
            key: const ValueKey('request-date'),
            controller: _date,
            keyboardType: TextInputType.datetime,
            decoration: InputDecoration(
              labelText: c.t(
                'Date · YYYY-MM-DD (Malaysia)',
                'Tarikh · YYYY-MM-DD (Malaysia)',
              ),
              helperText: c.t(
                'For example, 2026-10-23',
                'Contohnya, 2026-10-23',
              ),
            ),
            validator: (v) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v ?? '')
                ? null
                : c.t('Use YYYY-MM-DD.', 'Gunakan YYYY-MM-DD.'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('request-time'),
            controller: _time,
            keyboardType: TextInputType.datetime,
            decoration: InputDecoration(
              labelText: c.t(
                'Start time · HH:mm (MYT)',
                'Masa mula · HH:mm (MYT)',
              ),
            ),
            validator: (v) =>
                RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(v ?? '')
                ? null
                : c.t(
                    'Use a 24-hour time, e.g. 10:00.',
                    'Gunakan masa 24 jam, cth. 10:00.',
                  ),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<int>(
            key: const ValueKey('request-duration'),
            initialValue: _minutes,
            decoration: InputDecoration(
              labelText: c.t('Time together', 'Tempoh bersama'),
            ),
            items: [
              for (final n in [30, 60, 90])
                DropdownMenuItem(
                  value: n,
                  child: Text(c.t('$n minutes', '$n minit')),
                ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _minutes = v);
            },
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: _language,
            decoration: InputDecoration(
              labelText: c.t('Preferred language', 'Bahasa pilihan'),
            ),
            items: const [
              DropdownMenuItem(value: 'en', child: Text('English')),
              DropdownMenuItem(value: 'bm', child: Text('Bahasa Melayu')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _language = v);
            },
          ),
          const SizedBox(height: 18),
          TextFormField(
            key: const ValueKey('request-place'),
            controller: _place,
            maxLength: 160,
            decoration: InputDecoration(
              labelText: c.t('Meeting place', 'Tempat pertemuan'),
              hintText: c.t(
                'For example, the community hall entrance',
                'Contohnya, pintu masuk dewan komuniti',
              ),
            ),
            validator: (v) => v?.trim().isNotEmpty == true
                ? null
                : c.t('Enter a meeting place.', 'Masukkan tempat pertemuan.'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _note,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: c.t(
                'Anything helpful to know? (optional)',
                'Maklumat tambahan? (pilihan)',
              ),
              hintText: c.t(
                'For example, a slower walking pace.',
                'Contohnya, berjalan lebih perlahan.',
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: const TextStyle(color: Palette.gold),
                ),
              ),
            ),
          const SizedBox(height: 22),
          EmasButton(
            key: const ValueKey('review-request'),
            label: c.t('Review request', 'Semak permintaan'),
            icon: Icons.arrow_forward,
            onPressed: () => _prepare(c),
          ),
        ],
      ),
    );
  }

  Widget _reviewPage(
    PreviewController c,
    CompanionDraft draft,
    bool live,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _review = null),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: Text(c.t('Edit request', 'Edit permintaan')),
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
          live
              ? c.t('Not sent', 'Belum dihantar')
              : c.t('Sample request', 'Permintaan contoh'),
          gold: true,
        ),
      ),
      const SizedBox(height: 22),
      Surface(
        color: Palette.canvas,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in [
              (c.t('For', 'Untuk'), draft.elderName),
              (c.t('Activity / help', 'Aktiviti / bantuan'), draft.title),
              (
                c.t('Companion task', 'Tugas teman'),
                taskName(draft.task, c.malay),
              ),
              (
                c.t('When', 'Bila'),
                '${activityDate(draft.startsAt, c.malay)} · ${malaysiaTime(draft.startsAt)} MYT',
              ),
              (
                c.t('Time together', 'Tempoh bersama'),
                c.t('${draft.minutes} minutes', '${draft.minutes} minit'),
              ),
              (
                c.t('Language', 'Bahasa'),
                draft.language == 'bm' ? 'Bahasa Melayu' : 'English',
              ),
              (c.t('Meeting place', 'Tempat pertemuan'), draft.placeName),
              if (draft.note.isNotEmpty) (c.t('Note', 'Nota'), draft.note),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Palette.muted,
                      ),
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
      const SizedBox(height: 22),
      if (live) ...[
        EmasButton(
          label: c.t(
            'Not sent · booking unavailable',
            'Belum dihantar · tempahan belum tersedia',
          ),
          onPressed: null,
        ),
        const SizedBox(height: 18),
        const BookingConnectionNote(compact: true),
      ] else ...[
        Text(
          c.t(
            'This creates a sample request in this tab only. No coordinator is notified and no coins are earned.',
            'Ini mencipta permintaan contoh dalam tab ini sahaja. Tiada penyelaras dimaklumkan dan tiada syiling diperoleh.',
          ),
          style: const TextStyle(color: Palette.muted),
        ),
        const SizedBox(height: 18),
        EmasButton(
          key: const ValueKey('create-sample-request'),
          label: c.t('Create sample request', 'Cipta permintaan contoh'),
          icon: Icons.check,
          onPressed: () {
            var created = false;
            runSampleAction(context, () {
              c.demo.create(c.role, draft);
              created = true;
            });
            if (!created) return;
            Navigator.of(context).pop();
            c.navigate(destination: Destination.companion);
          },
        ),
      ],
    ],
  );
}

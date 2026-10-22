import 'package:flutter/material.dart';
import '../../app/preview_controller.dart';
import '../../models/backend_models.dart';
import '../../models/preview_models.dart';
import '../../shared/design_system.dart';
import '../../shared/park_art.dart';
import '../community/activity_catalog.dart';
import '../community/companion_workspace.dart';
import '../community/attendance_views.dart';
import '../wallet/wallet_view.dart';

String statusLabel(CheckInState? state, bool bm) => switch (state) {
  CheckInState.ok => bm ? 'Saya OK diterima' : 'Saya OK received',
  CheckInState.paused => bm ? 'Dijeda hari ini' : 'Paused today',
  CheckInState.pending => bm ? 'Menunggu daftar masuk' : 'Awaiting check-in',
  CheckInState.reminded =>
    bm ? 'Masa daftar masuk telah tiba' : 'Check-in is due',
  CheckInState.missed => bm ? 'Daftar masuk lewat' : 'Check-in overdue',
  null => bm ? 'Belum ada rekod hari ini' : 'No record for today yet',
};

class ConnectedHome extends StatelessWidget {
  const ConnectedHome({super.key});
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), s = c.session!;
    final p = s.profile;
    if (p == null) return const SizedBox.shrink();
    if (c.destination == Destination.rewards &&
        c.wallet != null &&
        [AppRole.elder, AppRole.helper].contains(p.role)) {
      return const WalletView();
    }
    if (c.role == AppRole.coordinator &&
        c.destination == Destination.activities) {
      return c.attendance == null
          ? const CompanionWorkspace()
          : const _CoordinatorRequests();
    }
    if (c.role == AppRole.coordinator &&
        c.destination == Destination.companion) {
      return const CommunityPlaces();
    }
    if (c.role != AppRole.coordinator &&
        c.destination == Destination.activities) {
      return const CommunityActivities();
    }
    if (c.role != AppRole.coordinator &&
        c.destination == Destination.companion) {
      return const CompanionWorkspace();
    }
    if (c.role == AppRole.helper && c.destination == Destination.today) {
      return const CompanionWorkspace();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            Pill(
              c.t('LOCAL BACKEND', 'PELAYAN SETEMPAT'),
              icon: Icons.cloud_done_outlined,
            ),
            Pill('${c.roleName(p.role)} · ${s.today} MYT'),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          p.displayName,
          style: TextStyle(
            fontSize: MediaQuery.sizeOf(context).width < 600 ? 30 : 37,
            height: 1.2,
            letterSpacing: -1,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          c.t(
            'A little reassurance for your everyday.',
            'Sedikit ketenangan untuk hari anda.',
          ),
          style: const TextStyle(color: Palette.muted),
        ),
        const SizedBox(height: 28),
        if (c.destination != Destination.today)
          PreviewEmpty(
            icon: Icons.hourglass_empty,
            title: c.navName(c.destination),
            description: c.t(
              'This feature is planned for a later backend stage. Explore the design preview from your account menu to see sample screens.',
              'Ciri ini dirancang untuk peringkat pelayan seterusnya. Teroka pratonton reka bentuk dari menu akaun untuk melihat skrin contoh.',
            ),
          )
        else ...[
          if (s.dataLoading) const LinearProgressIndicator(),
          if (s.dataError != null)
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.dataError!.message(c.malay)),
                  const SizedBox(height: 12),
                  EmasButton(
                    label: c.t('Retry connection', 'Cuba semula sambungan'),
                    onPressed: s.retryData,
                  ),
                ],
              ),
            )
          else
            switch (p.role) {
              AppRole.elder => const _ElderView(),
              AppRole.family => const _FamilyView(),
              AppRole.coordinator => const _CoordinatorView(),
              AppRole.helper => PreviewEmpty(
                icon: Icons.volunteer_activism_outlined,
                title: c.t('Welcome, helper', 'Selamat datang, pembantu'),
                description: c.t(
                  'Your account is connected. Availability, pairings, sessions and rewards will connect in later stages.',
                  'Akaun anda disambungkan. Ketersediaan, pasangan, sesi dan ganjaran akan disambungkan kemudian.',
                ),
              ),
            },
          const SizedBox(height: 24),
          Text(
            c.t(
              'Statuses refresh when backend commands run. Automatic reminders and notifications remain pending. Coin awards require approved earning rules.',
              'Status dikemas kini apabila arahan pelayan dijalankan. Peringatan automatik dan pemberitahuan masih belum tersedia. Ganjaran syiling memerlukan peraturan pendapatan yang diluluskan.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _CoordinatorRequests extends StatefulWidget {
  const _CoordinatorRequests();
  @override
  State<_CoordinatorRequests> createState() => _CoordinatorRequestsState();
}

class _CoordinatorRequestsState extends State<_CoordinatorRequests> {
  bool attendance = false;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const ValueKey('companion-requests-tab'),
              label: Text(c.t('Companion requests', 'Permintaan teman')),
              selected: !attendance,
              onSelected: (_) => setState(() => attendance = false),
            ),
            ChoiceChip(
              key: const ValueKey('attendance-review-tab'),
              label: Text(c.t('Attendance review', 'Semakan kehadiran')),
              selected: attendance,
              onSelected: (_) => setState(() => attendance = true),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (attendance)
          const AttendanceReviewQueue()
        else
          const CompanionWorkspace(),
      ],
    );
  }
}

class _ElderView extends StatelessWidget {
  const _ElderView();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), s = c.session!;
    final record = s.todayCheckIn;
    final paused = s.settings?.pausedToday(s.clock()) == true;
    final action = s.actions['checkin'];
    final done = record?.state == CheckInState.ok;
    final hero = Surface(
      color: Palette.green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            c.t('How are you today?', 'Apa khabar hari ini?'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 27,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              statusLabel(record?.state, c.malay),
              key: const ValueKey('elder-status'),
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
          if (record?.submittedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${malaysiaTime(record!.submittedAt)} MYT',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          const SizedBox(height: 18),
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            child: SizedBox(height: 150, child: ParkArt(dark: true)),
          ),
          const SizedBox(height: 20),
          EmasButton(
            label: done
                ? c.t('Checked in today', 'Sudah daftar masuk')
                : action?.busy == true
                ? c.t('Sending…', 'Menghantar…')
                : 'Saya OK',
            white: true,
            icon: Icons.check_circle_outline,
            onPressed:
                done ||
                    paused ||
                    s.dataLoading ||
                    s.settings == null ||
                    action != null
                ? null
                : s.checkIn,
          ),
          if (paused)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                c.t(
                  done
                      ? 'Today is paused in your settings. Your earlier response remains recorded.'
                      : 'Today is paused. Turn off Pause today and save before checking in.',
                  done
                      ? 'Hari ini dijeda dalam tetapan. Respons terdahulu kekal direkodkan.'
                      : 'Hari ini dijeda. Matikan Jeda hari ini dan simpan sebelum daftar masuk.',
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 880 && !c.largeText
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: hero),
                    const SizedBox(width: 24),
                    Expanded(child: _SettingsForm(settings: s.settings)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    hero,
                    const SizedBox(height: 24),
                    _SettingsForm(settings: s.settings),
                  ],
                ),
        ),
        ActionFeedback(name: 'checkin', retry: s.checkIn),
      ],
    );
  }
}

class _SettingsForm extends StatefulWidget {
  const _SettingsForm({required this.settings});
  final ElderSettings? settings;
  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  final _due = TextEditingController(), _grace = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool sharing = false, booking = false, pause = false, dirty = false;
  void _load() {
    final s = widget.settings;
    sharing = s?.sharing ?? false;
    booking = s?.booking ?? false;
    pause = s?.pausedToday(PreviewScope.of(context).session!.clock()) ?? false;
    _due.text = s?.dueLocalTime ?? '09:00';
    _grace.text = '${s?.graceMinutes ?? 30}';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!dirty) _load();
  }

  @override
  void didUpdateWidget(_SettingsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!dirty && oldWidget.settings != widget.settings) _load();
  }

  @override
  void dispose() {
    _due.dispose();
    _grace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), s = c.session!;
    final pending = s.actions['settings'];
    final enabled = pending == null && !s.dataLoading;
    Future<void> save() async {
      if (!_form.currentState!.validate()) return;
      await s.saveSettings({
        'familySharingEnabled': sharing,
        'familyBookingEnabled': booking,
        'dueLocalTime': _due.text,
        'graceMinutes': int.parse(_grace.text),
        'pauseToday': pause,
      });
      if (mounted && !s.actions.containsKey('settings')) {
        setState(() {
          dirty = false;
          _load();
        });
      }
    }

    return Surface(
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              c.t('Your check-in settings', 'Tetapan daftar masuk anda'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              c.t(
                'These permissions are separate. Changes apply after you save.',
                'Kebenaran ini berasingan. Perubahan digunakan selepas anda simpan.',
              ),
              style: const TextStyle(color: Palette.muted),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                c.t(
                  'Share daily status with family',
                  'Kongsi status harian dengan keluarga',
                ),
              ),
              subtitle: Text(
                c.t(
                  'Allows your linked family to see check-ins.',
                  'Benarkan keluarga terpaut melihat daftar masuk.',
                ),
              ),
              value: sharing,
              onChanged: enabled
                  ? (v) => setState(() {
                      sharing = v;
                      dirty = true;
                    })
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                c.t('Allow family booking', 'Benarkan tempahan keluarga'),
              ),
              subtitle: Text(
                c.t(
                  'Allows linked family to arrange companion requests.',
                  'Membenarkan keluarga terpaut mengatur permintaan teman.',
                ),
              ),
              value: booking,
              onChanged: enabled
                  ? (v) => setState(() {
                      booking = v;
                      dirty = true;
                    })
                  : null,
            ),
            const Divider(),
            TextFormField(
              controller: _due,
              enabled: enabled,
              decoration: InputDecoration(
                labelText: c.t(
                  'Due time (MYT · HH:mm)',
                  'Masa daftar masuk (MYT · HH:mm)',
                ),
              ),
              keyboardType: TextInputType.datetime,
              onChanged: (_) => dirty = true,
              validator: (v) =>
                  RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(v ?? '')
                  ? null
                  : c.t('Use HH:mm, e.g. 09:00.', 'Gunakan HH:mm, cth. 09:00.'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _grace,
              enabled: enabled,
              decoration: InputDecoration(
                labelText: c.t(
                  'Grace minutes (0–1440)',
                  'Minit tempoh ihsan (0–1440)',
                ),
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => dirty = true,
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return n != null && n >= 0 && n <= 1440
                    ? null
                    : c.t(
                        'Enter 0–1440 whole minutes.',
                        'Masukkan 0–1440 minit bulat.',
                      );
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(c.t('Pause today', 'Jeda hari ini')),
              subtitle: Text(
                c.t(
                  'Applies to today in Malaysia only.',
                  'Untuk hari ini di Malaysia sahaja.',
                ),
              ),
              value: pause,
              onChanged: enabled
                  ? (v) => setState(() {
                      pause = v;
                      dirty = true;
                    })
                  : null,
            ),
            const SizedBox(height: 16),
            EmasButton(
              label: pending?.busy == true
                  ? c.t('Saving…', 'Menyimpan…')
                  : c.t('Save settings', 'Simpan tetapan'),
              onPressed: enabled ? save : null,
            ),
            const SizedBox(height: 12),
            Text(
              widget.settings == null
                  ? c.t(
                      'No saved settings yet.',
                      'Belum ada tetapan tersimpan.',
                    )
                  : c.t(
                      'Saved on server · ${malaysiaTime(widget.settings!.updatedAt)} MYT',
                      'Disimpan pada pelayan · ${malaysiaTime(widget.settings!.updatedAt)} MYT',
                    ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            ActionFeedback(
              name: 'settings',
              retry: () async {
                await s.saveSettings({});
                if (mounted && !s.actions.containsKey('settings')) {
                  setState(() {
                    dirty = false;
                    _load();
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class ActionFeedback extends StatelessWidget {
  const ActionFeedback({super.key, required this.name, required this.retry});
  final String name;
  final Future<void> Function() retry;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), s = c.session!;
    final action = s.actions[name];
    if (action?.error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              action!.error!.message(c.malay),
              style: const TextStyle(color: Palette.gold),
            ),
          ),
          Text(
            c.t(
              'Retry uses the same confirmed action (${action.date}). Cancel to start a new one.',
              'Cuba semula menggunakan tindakan yang sama (${action.date}). Batal untuk tindakan baharu.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: action.busy ? null : retry,
                child: Text(c.t('Retry action', 'Cuba semula tindakan')),
              ),
              TextButton(
                onPressed: action.busy ? null : () => s.cancelAction(name),
                child: Text(
                  c.t('Cancel pending action', 'Batal tindakan tertunda'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FamilyView extends StatelessWidget {
  const _FamilyView();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), s = c.session!;
    final elder = s.selectedElder;
    final status = s.todayStatus;
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            c.t('Your family, with consent', 'Keluarga anda, dengan kebenaran'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 18),
          if (s.elders.isEmpty)
            Text(
              c.t(
                'No elder is linked to your household. No daily status is available.',
                'Tiada warga emas terpaut dengan isi rumah anda. Tiada status harian tersedia.',
              ),
            ),
          if (s.elders.length > 1)
            DropdownButtonFormField<String>(
              initialValue: s.selectedElderId,
              decoration: InputDecoration(
                labelText: c.t('Linked elder', 'Warga emas terpaut'),
              ),
              items: [
                for (final e in s.elders)
                  DropdownMenuItem(value: e.id, child: Text(e.displayName)),
              ],
              onChanged: (v) {
                if (v != null) s.selectElder(v);
              },
            ),
          if (elder != null) ...[
            Text(
              elder.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Pill(
                  c.t(
                    'Daily sharing: ${elder.sharing ? "on" : "off"}',
                    'Perkongsian harian: ${elder.sharing ? "aktif" : "tidak aktif"}',
                  ),
                ),
                Pill(
                  c.t(
                    'Booking consent: ${elder.booking ? "on" : "off"}',
                    'Kebenaran tempahan: ${elder.booking ? "aktif" : "tidak aktif"}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (!elder.sharing)
              Text(
                c.t(
                  'Daily status is private. Your elder has not enabled sharing.',
                  'Status harian adalah peribadi. Warga emas belum membenarkan perkongsian.',
                ),
                key: const ValueKey('family-private'),
              )
            else if (s.familyError != null) ...[
              Text(s.familyError!.message(c.malay)),
              TextButton(
                onPressed: s.retryData,
                child: Text(
                  c.t('Recheck permission', 'Semak semula kebenaran'),
                ),
              ),
            ] else ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  statusLabel(status?.state, c.malay),
                  key: const ValueKey('family-status'),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (status?.submittedAt != null)
                Text('${malaysiaTime(status!.submittedAt)} MYT'),
            ],
            const SizedBox(height: 20),
            Text(
              c.t(
                'Booking permission is independent of daily sharing. Open My companion to view permitted requests.',
                'Kebenaran tempahan berasingan daripada perkongsian harian. Buka Teman saya untuk melihat permintaan yang dibenarkan.',
              ),
              style: const TextStyle(color: Palette.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _CoordinatorView extends StatelessWidget {
  const _CoordinatorView();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), s = c.session!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Surface(
          color: Palette.soft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.t('Check-in follow-up', 'Susulan daftar masuk'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(
                c.t(
                  'Today’s reminded and missed records in your township. Seeded exceptions are demo scenarios, not delivered alerts.',
                  'Rekod perlu diingatkan dan terlepas hari ini dalam perbandaran anda. Pengecualian contoh bukan amaran yang dihantar.',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                c.t(
                  'Record a phone response only after speaking with the elder. This button records your report; it does not make a call.',
                  'Rekod respons telefon hanya selepas bercakap dengan warga emas. Butang ini merekod laporan anda; ia tidak membuat panggilan.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (!s.dataLoading && s.exceptions.isEmpty)
          Surface(
            child: Text(
              c.t(
                'No check-in exceptions for today.',
                'Tiada pengecualian daftar masuk hari ini.',
              ),
            ),
          ),
        for (final record in s.exceptions)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.elderId,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Pill(statusLabel(record.state, c.malay), gold: true),
                  const SizedBox(height: 12),
                  Text(
                    c.t(
                      'Due ${malaysiaTime(record.dueAt)} MYT',
                      'Masa daftar masuk ${malaysiaTime(record.dueAt)} MYT',
                    ),
                  ),
                  const SizedBox(height: 16),
                  EmasButton(
                    label: s.actions['phone:${record.elderId}']?.busy == true
                        ? c.t('Recording…', 'Merekod…')
                        : c.t('Record phone response', 'Rekod respons telefon'),
                    onPressed: s.actions.containsKey('phone:${record.elderId}')
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(
                                  c.t(
                                    'Confirm elder response',
                                    'Sahkan respons warga emas',
                                  ),
                                ),
                                content: Text(
                                  c.t(
                                    'Have you spoken with ${record.elderId} and confirmed they are OK? This records your report and does not initiate a call.',
                                    'Adakah anda bercakap dengan ${record.elderId} dan mengesahkan mereka OK? Ini merekod laporan dan tidak membuat panggilan.',
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: Text(c.t('Cancel', 'Batal')),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: Text(
                                      c.t(
                                        'Yes, record response',
                                        'Ya, rekod respons',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true && context.mounted) {
                              s.phoneResponse(record.elderId);
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
        for (final name
            in s.actions.keys.where((n) => n.startsWith('phone:')).toList())
          ActionFeedback(
            name: name,
            retry: () => s.phoneResponse(name.substring(6)),
          ),
      ],
    );
  }
}

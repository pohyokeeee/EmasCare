import 'package:flutter/material.dart';
import '../../app/app_shell.dart';
import '../../app/preview_controller.dart';
import '../../models/backend_models.dart';
import '../../models/community_models.dart';
import '../../models/companion_ui_models.dart';
import '../../models/preview_models.dart';
import '../../shared/design_system.dart';
import 'community_ui.dart';
import 'request_form.dart';
import 'live_session_workspace.dart';

class CompanionWorkspace extends StatelessWidget {
  const CompanionWorkspace({super.key});
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    final live = c.session?.connected == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommunityHeading(
          switch (c.role) {
            AppRole.coordinator => c.t(
              'A little care, well coordinated.',
              'Sedikit perhatian, diselaraskan rapi.',
            ),
            AppRole.helper => c.t(
              'Good company starts with you.',
              'Teman yang baik bermula dengan anda.',
            ),
            AppRole.family => c.t(
              'A helping hand for their day.',
              'Bantuan untuk memudahkan hari mereka.',
            ),
            AppRole.elder => c.t(
              'Your companion. Your pace.',
              'Teman anda. Mengikut rentak anda.',
            ),
          },
          c.t(
            'Familiar people, clear plans and a little more confidence.',
            'Wajah dikenali, rancangan jelas dan sedikit keyakinan tambahan.',
          ),
        ),
        if (live && c.sessions != null)
          const LiveSessionWorkspace()
        else if (live)
          const _ConnectedCompanions()
        else
          const _SampleCompanions(),
      ],
    );
  }
}

class _ConnectedCompanions extends StatelessWidget {
  const _ConnectedCompanions();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), community = c.community;
    final family = c.role == AppRole.family;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (community?.catalogError != null) ...[
          CommunityError(
            community!.catalogError!.message(c.malay),
            retry: community.retry,
          ),
          const SizedBox(height: 18),
        ],
        if (c.role == AppRole.helper) ...[
          const HelperAvailabilityCard(),
          const SizedBox(height: 20),
        ],
        if (family) ...[
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  c.t(
                    'Family companion updates',
                    'Kemas kini teman keluarga',
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (c.session!.elders.isEmpty)
                  Text(
                    c.t(
                      'No elder is linked to your household.',
                      'Tiada warga emas terpaut dengan isi rumah anda.',
                    ),
                  )
                else ...[
                  if (c.session!.elders.length > 1)
                    DropdownButtonFormField<String>(
                      key: ValueKey(c.session!.selectedElderId),
                      initialValue: c.session!.selectedElderId,
                      decoration: InputDecoration(
                        labelText: c.t('Linked elder', 'Warga emas terpaut'),
                      ),
                      items: [
                        for (final e in c.session!.elders)
                          DropdownMenuItem(
                            value: e.id,
                            child: Text(e.displayName),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) c.session!.selectElder(v);
                      },
                    ),
                  Text(
                    c.session!.selectedElder?.displayName ?? '',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Pill(
                    c.session!.selectedElder?.booking == true
                        ? c.t(
                            'Booking consent is on',
                            'Kebenaran tempahan aktif',
                          )
                        : c.t(
                            'Booking consent is off',
                            'Kebenaran tempahan tidak aktif',
                          ),
                    icon: Icons.verified_user_outlined,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    c.t(
                      'Your elder controls booking consent. It is separate from sharing their daily check-in.',
                      'Warga emas mengawal kebenaran tempahan. Ini berasingan daripada perkongsian daftar masuk harian.',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ] else if (community?.pairingError != null)
          CommunityError(
            community!.pairingError!.message(c.malay),
            retry: community.retry,
          )
        else if (community?.pairingLoading == true)
          const LinearProgressIndicator()
        else if (community?.pairings.isEmpty ?? true)
          PreviewEmpty(
            icon: Icons.people_outline,
            title: c.t(
              'No regular pairing recorded yet',
              'Belum ada pasangan tetap direkodkan',
            ),
            description: c.t(
              'An accepted pairing will appear here when your coordinator arranges it.',
              'Pasangan yang diterima akan dipaparkan di sini selepas diatur oleh penyelaras.',
            ),
          )
        else
          for (final pair in community!.pairings)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: _PairingCard(pair),
            ),
        const SizedBox(height: 20),
        if (c.role == AppRole.elder) ...[
          EmasButton(
            label: c.t(
              'Preview a companion request',
              'Pratonton permintaan teman',
            ),
            icon: Icons.edit_calendar_outlined,
            onPressed: () => openCompanionRequest(context),
          ),
          const SizedBox(height: 20),
        ],
        const BookingConnectionNote(),
      ],
    );
  }
}

class _PairingCard extends StatelessWidget {
  const _PairingCard(this.pair);
  final PairingRecord pair;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconTile(Icons.people_outline),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.t(
                        'Your regular companion pairing',
                        'Pasangan teman tetap anda',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      pair.accepted
                          ? c.t(
                              'Accepted by both participants',
                              'Diterima oleh kedua-dua peserta',
                            )
                          : c.t(
                              'Acceptance is not complete',
                              'Penerimaan belum lengkap',
                            ),
                      style: const TextStyle(color: Palette.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pill(
                pair.active
                    ? c.t('Active pairing', 'Pasangan aktif')
                    : c.t('Inactive pairing', 'Pasangan tidak aktif'),
              ),
              if (pair.demoSeed)
                Pill(
                  c.t('Seeded trial pairing', 'Pasangan percubaan contoh'),
                  gold: true,
                ),
            ],
          ),
          if (pair.trialStartsOn != null && pair.trialEndsOn != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                c.t(
                  'Trial: ${pair.trialStartsOn} to ${pair.trialEndsOn}',
                  'Percubaan: ${pair.trialStartsOn} hingga ${pair.trialEndsOn}',
                ),
                style: const TextStyle(color: Palette.muted),
              ),
            ),
          if (c.role == AppRole.coordinator)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '${pair.elderId} ↔ ${pair.helperId}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          Text(
            c.t(
              'This pairing is not a booked session.',
              'Pasangan ini bukan sesi yang telah ditempah.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class HelperAvailabilityCard extends StatelessWidget {
  const HelperAvailabilityCard({super.key});
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    final live = c.session?.connected == true;
    final helper = c.community?.helper;
    if (live && c.community?.helperError != null) {
      return CommunityError(
        c.community!.helperError!.message(c.malay),
        retry: c.community!.retry,
      );
    }
    final available = live
        ? helper?.available ?? false
        : c.repository.helperAvailable;
    return Surface(
      color: Palette.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            c.t('Room for a little company?', 'Ada masa untuk menemani?'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            c.t(
              'Your availability helps the coordinator make a comfortable match.',
              'Ketersediaan anda membantu penyelaras mencari padanan yang sesuai.',
            ),
            style: const TextStyle(color: Palette.muted),
          ),
          const SizedBox(height: 14),
          if (live && c.community?.helperLoading == true)
            const LinearProgressIndicator()
          else if (live && helper == null)
            Text(
              c.t(
                'No helper profile is recorded yet.',
                'Profil pembantu belum direkodkan.',
              ),
            )
          else ...[
            SwitchListTile(
              key: const ValueKey('helper-availability'),
              contentPadding: EdgeInsets.zero,
              title: Text(c.t('Available to help', 'Sedia membantu')),
              value: available,
              onChanged: live ? null : c.repository.previewSetAvailability,
            ),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                Pill(
                  !live || helper!.approved
                      ? c.t('Approved helper', 'Pembantu diluluskan')
                      : c.t('Approval pending', 'Menunggu kelulusan'),
                  icon: Icons.verified_outlined,
                ),
                Pill(
                  live
                      ? helper!.languages
                            .map((s) => s.toUpperCase())
                            .join(' / ')
                      : 'BM / EN',
                ),
                if (!live)
                  Pill(
                    c.t('Sample availability', 'Ketersediaan contoh'),
                    gold: true,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              live
                  ? c.t(
                      'Availability changes are not connected yet. This is your saved profile state.',
                      'Perubahan ketersediaan belum disambungkan. Ini ialah status profil tersimpan anda.',
                    )
                  : c.t(
                      'Sample hours: every day, 08:00–18:00 MYT. Changes stay in this tab.',
                      'Waktu contoh: setiap hari, 08:00–18:00 MYT. Perubahan kekal dalam tab ini.',
                    ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (live && helper!.slots.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  c.t('View availability hours', 'Lihat waktu ketersediaan'),
                  style: const TextStyle(fontSize: 13),
                ),
                children: [
                  for (final slot in helper.slots)
                    if (slot['weekday'] is int &&
                        (slot['weekday'] as int) >= 1 &&
                        (slot['weekday'] as int) <= 7)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          '${(c.malay ? ['Isn', 'Sel', 'Rab', 'Kha', 'Jum', 'Sab', 'Ahd'] : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])[(slot['weekday'] as int) - 1]} · ${_minute(slot['startMinute'])}–${_minute(slot['endMinute'])} MYT',
                        ),
                      ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  String _minute(Object? value) => value is int && value >= 0 && value <= 1440
      ? '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}'
      : '—';
}

class _SampleCompanions extends StatelessWidget {
  const _SampleCompanions();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), demo = c.demo;
    final family = c.role == AppRole.family;
    final canRequest = c.role == AppRole.elder;
    final requests = demo.requests
        .where((r) => c.role != AppRole.helper || r.helperName != null)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SampleJourneyBanner(),
        if (c.role == AppRole.helper) ...[
          const HelperAvailabilityCard(),
          const SizedBox(height: 22),
        ],
        if (c.role == AppRole.elder || family) ...[
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Avatar('KL', size: 54),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kak Lina',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            c.t(
                              'Regular companion · accepted sample pairing',
                              'Teman tetap · pasangan contoh diterima',
                            ),
                            style: const TextStyle(color: Palette.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Pill('BM / EN'),
                    Pill(
                      demo.helperAvailable
                          ? c.t('Available', 'Tersedia')
                          : c.t('Unavailable', 'Tidak tersedia'),
                      icon: Icons.schedule,
                    ),
                  ],
                ),
                if (c.role == AppRole.elder)
                  SwitchListTile(
                    key: const ValueKey('sample-booking-consent'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      c.t(
                        'Share companion updates with family',
                        'Kongsi kemas kini teman dengan keluarga',
                      ),
                    ),
                    subtitle: Text(
                      c.t(
                        'Only the elder changes this permission. Family cannot create requests; daily sharing is separate.',
                        'Hanya warga emas mengubah kebenaran ini. Keluarga tidak boleh mencipta permintaan; perkongsian harian adalah berasingan.',
                      ),
                    ),
                    value: demo.familyBooking,
                    onChanged: (v) => demo.setFamilyBooking(c.role, v),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Pill(
                      demo.familyBooking
                          ? c.t(
                              'Booking consent is on',
                              'Kebenaran tempahan aktif',
                            )
                          : c.t(
                              'Booking consent is off',
                              'Kebenaran tempahan tidak aktif',
                            ),
                    ),
                  ),
                const SizedBox(height: 18),
                if (canRequest)
                  EmasButton(
                    label: c.t(
                      'New sample request',
                      'Permintaan contoh baharu',
                    ),
                    icon: Icons.add,
                    onPressed: () => openCompanionRequest(context),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 26),
        ],
        if (family && !demo.familyBooking)
          PreviewEmpty(
            icon: Icons.lock_outline,
            title: c.t(
              'Family companion updates are off.',
              'Kemas kini teman keluarga tidak aktif.',
            ),
            description: c.t(
              'Ask your elder to share companion updates. Family cannot create requests or confirm attendance on the elder’s behalf.',
              'Minta warga emas berkongsi kemas kini teman. Keluarga tidak boleh mencipta permintaan atau mengesahkan kehadiran bagi pihak warga emas.',
            ),
          )
        else ...[
          TitleRow(
            c.role == AppRole.coordinator
                ? c.t('Requests to arrange', 'Permintaan untuk diatur')
                : c.t('Your requests & sessions', 'Permintaan & sesi anda'),
          ),
          if (requests.isEmpty)
            PreviewEmpty(
              icon: Icons.event_available_outlined,
              title: c.t(
                'A little space for what comes next.',
                'Ruang untuk rancangan seterusnya.',
              ),
              description: c.role == AppRole.coordinator
                  ? c.t(
                      'Switch to Elder or Family in the preview role menu and create a sample request. Then return here to assign the companion.',
                      'Tukar ke Warga emas atau Keluarga dalam menu pratonton dan cipta permintaan contoh. Kemudian kembali untuk menetapkan teman.',
                    )
                  : c.role == AppRole.helper
                  ? c.t(
                      'Assigned sample sessions will appear here. A coordinator assigns the accepted regular companion first.',
                      'Sesi contoh yang ditetapkan akan dipaparkan di sini. Penyelaras menetapkan teman tetap yang diterima dahulu.',
                    )
                  : c.t(
                      'Browse an activity or create a request for a little help. You stay in control of the plan.',
                      'Lihat aktiviti atau cipta permintaan bantuan. Anda mengawal rancangan sendiri.',
                    ),
            ),
          for (final r in requests)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _SampleSessionCard(r),
            ),
        ],
        const SizedBox(height: 20),
        Text(
          c.t(
            'No coins are credited in this sample journey. A completed session requires two distinct confirmations.',
            'Tiada syiling dikreditkan dalam perjalanan contoh. Sesi lengkap memerlukan dua pengesahan berasingan.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _SampleSessionCard extends StatelessWidget {
  const _SampleSessionCard(this.request);
  final DemoCompanionRequest request;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), r = request, d = request.draft;
    final confirming =
        r.stage == DemoSessionStage.awaitingConfirmation ||
        r.stage == DemoSessionStage.completed;
    final early = [
      DemoSessionStage.requested,
      DemoSessionStage.assigned,
      DemoSessionStage.accepted,
    ].contains(r.stage);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pill(
                stageName(r.stage, c.malay),
                gold: r.stage == DemoSessionStage.cancelled,
              ),
              Pill(c.t('Sample', 'Contoh')),
            ],
          ),
          const SizedBox(height: 18),
          Text(d.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '${activityDate(d.startsAt, c.malay)} · ${malaysiaTime(d.startsAt)} MYT · ${d.minutes} ${c.t("min", "minit")}',
            style: const TextStyle(color: Palette.muted),
          ),
          const SizedBox(height: 8),
          Text(d.placeName),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pill(d.elderName, icon: Icons.person_outline),
              if (r.helperName != null)
                Pill(r.helperName!, icon: Icons.people_outline),
              Pill(taskName(d.task, c.malay)),
            ],
          ),
          if (d.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(d.note, style: const TextStyle(color: Palette.muted)),
            ),
          const SizedBox(height: 24),
          _SessionTimeline(r.stage),
          if (confirming) ...[
            const Divider(),
            Text(
              c.t(
                'Two people, two confirmations.',
                'Dua peserta, dua pengesahan.',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _ConfirmationLine(d.elderName, r.elderConfirmed),
            _ConfirmationLine(
              r.helperName ?? c.t('Helper', 'Pembantu'),
              r.helperConfirmed,
            ),
            const SizedBox(height: 12),
            if (r.stage != DemoSessionStage.completed)
              Text(
                c.t(
                  'The session stays incomplete until the elder and helper each confirm.',
                  'Sesi belum lengkap sehingga warga emas dan pembantu masing-masing mengesahkan.',
                ),
                style: const TextStyle(color: Palette.muted),
              ),
          ],
          const SizedBox(height: 20),
          if (c.role == AppRole.coordinator &&
              r.stage == DemoSessionStage.requested)
            EmasButton(
              label: c.t('Choose companion', 'Pilih teman'),
              icon: Icons.person_add_alt_1,
              onPressed: () => _chooseCompanion(context, r),
            ),
          if (c.role == AppRole.helper)
            switch (r.stage) {
              DemoSessionStage.assigned => EmasButton(
                label: c.t('Accept session', 'Terima sesi'),
                onPressed: () =>
                    runSampleAction(context, () => c.demo.accept(c.role, r)),
              ),
              DemoSessionStage.accepted => EmasButton(
                label: c.t('Start session', 'Mulakan sesi'),
                onPressed: () =>
                    runSampleAction(context, () => c.demo.start(c.role, r)),
              ),
              DemoSessionStage.inProgress => EmasButton(
                label: c.t('Finish session', 'Tamatkan sesi'),
                onPressed: () =>
                    runSampleAction(context, () => c.demo.finish(c.role, r)),
              ),
              DemoSessionStage.awaitingConfirmation => EmasButton(
                label: r.helperConfirmed
                    ? c.t('You have confirmed', 'Anda telah mengesahkan')
                    : c.t('Confirm my participation', 'Sahkan penyertaan saya'),
                onPressed: r.helperConfirmed
                    ? null
                    : () => runSampleAction(
                        context,
                        () => c.demo.confirm(c.role, r),
                      ),
              ),
              _ => const SizedBox.shrink(),
            },
          if (c.role == AppRole.elder &&
              r.stage == DemoSessionStage.awaitingConfirmation)
            EmasButton(
              label: r.elderConfirmed
                  ? c.t('You have confirmed', 'Anda telah mengesahkan')
                  : c.t('Confirm my participation', 'Sahkan penyertaan saya'),
              onPressed: r.elderConfirmed
                  ? null
                  : () => runSampleAction(
                      context,
                      () => c.demo.confirm(c.role, r),
                    ),
            ),
          if (c.role == AppRole.family && confirming)
            Text(
              c.t(
                'Only the elder and helper can confirm their own participation.',
                'Hanya warga emas dan pembantu boleh mengesahkan penyertaan sendiri.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (early && c.role != AppRole.helper)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(
                        c.t(
                          'Cancel this sample request?',
                          'Batal permintaan contoh ini?',
                        ),
                      ),
                      content: Text(
                        c.t(
                          'The sample request will be marked cancelled. You can create another request afterwards.',
                          'Permintaan contoh akan ditandakan dibatalkan. Anda boleh mencipta permintaan lain selepas itu.',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(
                            c.t('Keep request', 'Kekalkan permintaan'),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(
                            c.t('Cancel request', 'Batal permintaan'),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    runSampleAction(context, () => c.demo.cancel(c.role, r));
                  }
                },
                child: Text(
                  c.t('Cancel sample request', 'Batal permintaan contoh'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConfirmationLine extends StatelessWidget {
  const _ConfirmationLine(this.name, this.confirmed);
  final String name;
  final bool confirmed;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            confirmed
                ? Icons.check_circle_outline
                : Icons.radio_button_unchecked,
            size: 20,
            color: confirmed ? Palette.green : Palette.muted,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(name)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              confirmed
                  ? c.t('Confirmed', 'Disahkan')
                  : c.t('Waiting', 'Menunggu'),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12, color: Palette.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTimeline extends StatelessWidget {
  const _SessionTimeline(this.stage);
  final DemoSessionStage stage;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    if (stage == DemoSessionStage.cancelled) {
      return Text(
        c.t(
          'Cancelled sample requests cannot complete or earn rewards.',
          'Permintaan contoh yang dibatalkan tidak boleh dilengkapkan atau memperoleh ganjaran.',
        ),
        style: const TextStyle(color: Palette.muted),
      );
    }
    final current = switch (stage) {
      DemoSessionStage.requested => 0,
      DemoSessionStage.assigned => 1,
      DemoSessionStage.accepted || DemoSessionStage.inProgress => 2,
      DemoSessionStage.awaitingConfirmation => 3,
      DemoSessionStage.completed => 4,
      _ => 0,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: Semantics(
              label:
                  '${[c.t("Request", "Permintaan"), c.t("Companion", "Teman"), c.t("Session", "Sesi"), c.t("Both confirm", "Kedua-duanya sahkan")][i]}: ${i < current
                      ? c.t("done", "selesai")
                      : i == current
                      ? c.t("current", "semasa")
                      : c.t("upcoming", "akan datang")}',
              child: Column(
                children: [
                  Icon(
                    i < current
                        ? Icons.check_circle
                        : i == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 21,
                    color: i <= current ? Palette.green : Palette.line,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Text(
                      [
                        c.t('Request', 'Permintaan'),
                        c.t('Companion', 'Teman'),
                        c.t('Session', 'Sesi'),
                        c.t('Both confirm', 'Kedua-duanya sahkan'),
                      ][i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: i <= current ? Palette.green : Palette.muted,
                        fontWeight: i == current
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

void _chooseCompanion(BuildContext context, DemoCompanionRequest request) {
  final c = PreviewScope.of(context);
  showEmasSheet(
    context,
    CommunitySheetGuard(token: scopeToken(c), child: _ChooseCompanion(request)),
  );
}

class _ChooseCompanion extends StatelessWidget {
  const _ChooseCompanion(this.request);
  final DemoCompanionRequest request;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), demo = c.demo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          c.t(
            'A familiar face for this plan.',
            'Wajah dikenali untuk rancangan ini.',
          ),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 18),
        const SampleJourneyBanner(),
        Surface(
          color: Palette.soft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Avatar('KL', size: 56),
              const SizedBox(height: 16),
              Text('Kak Lina', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                c.t(
                  'Mr Tan’s accepted regular companion. This sample has one approved pairing; it is not a matching marketplace.',
                  'Teman tetap Mr Tan yang diterima. Contoh ini mempunyai satu pasangan diluluskan; ini bukan pasaran pemadanan.',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Pill(
                    c.t('Approved', 'Diluluskan'),
                    icon: Icons.verified_outlined,
                  ),
                  const Pill('BM / EN'),
                  Pill(
                    demo.helperAvailable
                        ? c.t('Available', 'Tersedia')
                        : c.t('Unavailable', 'Tidak tersedia'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                c.t(
                  'Sample hours: 08:00–18:00 MYT, every day.',
                  'Waktu contoh: 08:00–18:00 MYT, setiap hari.',
                ),
                style: const TextStyle(color: Palette.muted),
              ),
            ],
          ),
        ),
        if (!demo.canAssign(request))
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text(
              c.t(
                'This helper is unavailable for the requested plan. Change availability in the Helper preview or choose a time within the sample hours.',
                'Pembantu tidak tersedia untuk rancangan ini. Ubah ketersediaan dalam pratonton Pembantu atau pilih masa dalam waktu contoh.',
              ),
              style: const TextStyle(color: Palette.gold),
            ),
          ),
        const SizedBox(height: 22),
        EmasButton(
          label: c.t('Assign sample companion', 'Tetapkan teman contoh'),
          onPressed: c.role == AppRole.coordinator && demo.canAssign(request)
              ? () {
                  var assigned = false;
                  runSampleAction(context, () {
                    demo.assign(c.role, request);
                    assigned = true;
                  });
                  if (assigned) Navigator.pop(context);
                }
              : null,
        ),
      ],
    );
  }
}

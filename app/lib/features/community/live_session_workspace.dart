import 'package:flutter/material.dart';
import '../../app/app_shell.dart';
import '../../app/preview_controller.dart';
import '../../models/backend_models.dart';
import '../../models/community_models.dart';
import '../../models/preview_models.dart';
import '../../models/session_models.dart';
import '../../shared/design_system.dart';
import 'community_ui.dart';
import 'live_availability.dart';
import 'request_form.dart';
import 'session_ui.dart';

class LiveSessionWorkspace extends StatelessWidget {
  const LiveSessionWorkspace({super.key});
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.sessions!;
    final family = c.role == AppRole.family,
        coordinator = c.role == AppRole.coordinator;
    final canBook =
        c.role == AppRole.elder ||
        (family && c.session!.selectedElder?.booking == true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.role == AppRole.helper) ...[
          const LiveAvailabilityCard(),
          const SizedBox(height: 24),
        ],
        if (family) ...[
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  c.t(
                    'Family booking permission',
                    'Kebenaran tempahan keluarga',
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
                  DropdownButtonFormField<String>(
                    key: ValueKey(c.session!.selectedElderId),
                    initialValue: c.session!.selectedElderId,
                    isExpanded: true,
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
                    onChanged: (id) {
                      if (id != null) c.session!.selectElder(id);
                    },
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Pill(
                      canBook
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
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  c.t(
                    'Your elder controls booking permission. Daily check-in sharing is a separate choice.',
                    'Warga emas mengawal kebenaran tempahan. Perkongsian daftar masuk harian ialah pilihan berasingan.',
                  ),
                  style: const TextStyle(color: Palette.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
        ],
        if (c.role == AppRole.elder) ...[
          if (c.community?.pairings.isNotEmpty == true)
            Surface(
              color: Palette.soft,
              child: Row(
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
                          c.community!.pairings.any((p) => p.accepted)
                              ? c.t(
                                  'Accepted by both participants. A coordinator arranges each session.',
                                  'Diterima oleh kedua-dua peserta. Penyelaras mengatur setiap sesi.',
                                )
                              : c.t(
                                  'Pairing acceptance is not complete yet.',
                                  'Penerimaan pasangan belum lengkap.',
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
        ],
        if (c.role == AppRole.elder || family) ...[
          EmasButton(
            label: c.t('New request', 'Permintaan baharu'),
            icon: Icons.add,
            onPressed: canBook ? () => openCompanionRequest(context) : null,
          ),
          const SizedBox(height: 26),
        ],
        if (coordinator) ...[
          DropdownButtonFormField<RequestState>(
            initialValue: w.queue,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: c.t('Request queue', 'Senarai permintaan'),
            ),
            items: [
              for (final s in RequestState.values)
                DropdownMenuItem(
                  value: s,
                  child: Text(requestStateLabel(s, c.malay)),
                ),
            ],
            onChanged: (s) {
              if (s != null) w.selectQueue(s);
            },
          ),
          const SizedBox(height: 24),
        ],
        for (final item
            in w.actions.entries
                .where(
                  (e) =>
                      e.value.kind == 'create' ||
                      e.value.kind == 'availability',
                )
                .toList()) ...[
          Text(
            item.value.kind == 'create'
                ? c.t(
                    'Request awaiting a response',
                    'Permintaan menunggu jawapan',
                  )
                : c.t(
                    'Availability awaiting a response',
                    'Ketersediaan menunggu jawapan',
                  ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          PendingSessionAction(item.key),
          const SizedBox(height: 18),
        ],
        TitleRow(
          coordinator
              ? c.t('Requests to arrange', 'Permintaan untuk diatur')
              : c.t('Your requests & sessions', 'Permintaan & sesi anda'),
        ),
        if (w.error != null)
          CommunityError(w.error!.message(c.malay), retry: w.retry)
        else if (family && !canBook)
          PreviewEmpty(
            icon: Icons.lock_outline,
            title: c.t(
              'Booking permission is off.',
              'Kebenaran tempahan tidak aktif.',
            ),
            description: c.t(
              'Requests are hidden until your elder allows family booking. You cannot confirm participation on their behalf.',
              'Permintaan disembunyikan sehingga warga emas membenarkan tempahan keluarga. Anda tidak boleh mengesahkan penyertaan bagi pihak mereka.',
            ),
          )
        else if (w.loading)
          const LinearProgressIndicator()
        else if (w.requests.isEmpty)
          PreviewEmpty(
            icon: Icons.event_available_outlined,
            title: c.t(
              'A little space for what comes next.',
              'Ruang untuk rancangan seterusnya.',
            ),
            description: coordinator
                ? c.t(
                    'No requests in this queue. Choose another status to review existing sessions.',
                    'Tiada permintaan dalam senarai ini. Pilih status lain untuk menyemak sesi sedia ada.',
                  )
                : c.role == AppRole.helper
                ? c.t(
                    'Sessions appear here when your coordinator assigns you.',
                    'Sesi dipaparkan di sini apabila penyelaras menetapkannya kepada anda.',
                  )
                : c.t(
                    'Browse an activity or request a little help. Your saved plans will appear here.',
                    'Lihat aktiviti atau minta sedikit bantuan. Rancangan tersimpan dipaparkan di sini.',
                  ),
          )
        else
          for (final r in w.requests)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _LiveSessionCard(r),
            ),
        const SizedBox(height: 16),
        Text(
          c.t(
            'Verified participation follows the saved reward rules. Each actual participant has their own wallet.',
            'Penyertaan yang disahkan mengikut dasar ganjaran tersimpan. Setiap peserta sebenar mempunyai dompet sendiri.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _LiveSessionCard extends StatelessWidget {
  const _LiveSessionCard(this.r);
  final SessionRequest r;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.sessions!;
    final name = 'request:${r.id}',
        pending = w.actions.containsKey('request:${r.id}');
    final activity = c.community?.activities
        .where((a) => a.id == r.activityId)
        .firstOrNull;
    final place = c.community?.places
        .where((p) => p.id == r.placeId)
        .firstOrNull;
    final confirming =
        r.state == RequestState.awaitingConfirmation ||
        r.state == RequestState.completed;
    final helper =
        c.role == AppRole.helper && r.helperId == c.session!.profile!.uid;
    final elder =
        c.role == AppRole.elder && r.elderId == c.session!.profile!.uid;
    final startAllowed =
        !w.now.isBefore(r.startsAt) &&
        (r.activityId == null || w.now.isBefore(r.endsAt));
    final finishAllowed = r.activityId == null || !w.now.isBefore(r.endsAt);
    Future<void> action(String value) async {
      final saved = await w.transition(r.id, value);
      if (context.mounted && saved) {
        sessionToast(context, 'Session updated.', 'Sesi dikemas kini.');
      }
    }

    return Surface(
      key: ValueKey('live-request-${r.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pill(
                requestStateLabel(r.state, c.malay),
                gold: r.state == RequestState.cancelled,
              ),
              Pill(c.t('Saved', 'Disimpan'), icon: Icons.cloud_done_outlined),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            activity?.title.inLanguage(c.malay) ??
                sessionTask(r.taskType, c.malay),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            sessionWhen(r.startsAt, r.endsAt, c.malay),
            style: const TextStyle(color: Palette.muted),
          ),
          const SizedBox(height: 8),
          Text(
            r.taskType == 'phone_help'
                ? c.t(
                    'By phone · no meeting place',
                    'Melalui telefon · tiada tempat pertemuan',
                  )
                : place?.name ??
                      c.t(
                        'Place reference: ${r.placeId}',
                        'Rujukan tempat: ${r.placeId}',
                      ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pill(r.elderName, icon: Icons.person_outline),
              if (r.helperName != null)
                Pill(r.helperName!, icon: Icons.people_outline),
              Pill(sessionTask(r.taskType, c.malay)),
              Pill(r.preferredLanguage.toUpperCase()),
            ],
          ),
          const SizedBox(height: 22),
          _LiveTimeline(r.state),
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
            for (final (person, done) in [
              (r.elderName, r.elderConfirmed),
              (r.helperName ?? c.t('Helper', 'Pembantu'), r.helperConfirmed),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      done ? Icons.check_circle_outline : Icons.schedule,
                      size: 18,
                      color: done ? Palette.green : Palette.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(person)),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        done
                            ? c.t('Confirmed', 'Disahkan')
                            : c.t('Waiting', 'Menunggu'),
                        style: const TextStyle(color: Palette.muted),
                      ),
                    ),
                  ],
                ),
              ),
            if (r.state != RequestState.completed)
              Text(
                c.t(
                  'The session stays incomplete until the elder and helper each confirm.',
                  'Sesi belum lengkap sehingga warga emas dan pembantu masing-masing mengesahkan.',
                ),
                style: const TextStyle(color: Palette.muted),
              ),
            if (c.role == AppRole.family || c.role == AppRole.coordinator)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  c.t(
                    'Only the two participants can confirm for themselves.',
                    'Hanya kedua-dua peserta boleh mengesahkan penyertaan sendiri.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (r.completedAt != null)
              Text(
                c.t(
                  'Completed ${activityDate(r.completedAt!, c.malay)} · ${malaysiaTime(r.completedAt)} MYT',
                  'Lengkap ${activityDate(r.completedAt!, c.malay)} · ${malaysiaTime(r.completedAt)} MYT',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
          const SizedBox(height: 18),
          if (c.role == AppRole.coordinator &&
              r.state == RequestState.requested)
            EmasButton(
              label: c.t('Choose companion', 'Pilih teman'),
              icon: Icons.person_add_alt_1,
              onPressed: pending
                  ? null
                  : () => showEmasSheet(
                      context,
                      CommunitySheetGuard(
                        token: scopeToken(c),
                        child: _AssignmentSheet(r.id),
                      ),
                    ),
            ),
          if (helper && r.state == RequestState.assigned)
            EmasButton(
              label: c.t('Accept session', 'Terima sesi'),
              onPressed: pending ? null : () => action('accept'),
            ),
          if (helper && r.state == RequestState.accepted) ...[
            if (!startAllowed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  w.now.isBefore(r.startsAt)
                      ? c.t(
                          'Start is available at ${malaysiaTime(r.startsAt)} MYT on ${activityDate(r.startsAt, c.malay)}.',
                          'Sesi boleh dimulakan pada ${malaysiaTime(r.startsAt)} MYT, ${activityDate(r.startsAt, c.malay)}.',
                        )
                      : c.t(
                          'This activity has ended. The session can no longer start.',
                          'Aktiviti ini telah tamat. Sesi tidak boleh dimulakan lagi.',
                        ),
                ),
              ),
            EmasButton(
              label: c.t('Start session', 'Mulakan sesi'),
              onPressed: pending || !startAllowed
                  ? null
                  : () => action('start'),
            ),
          ],
          if (helper && r.state == RequestState.inProgress) ...[
            if (!finishAllowed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  c.t(
                    'Finish after the activity ends at ${malaysiaTime(r.endsAt)} MYT.',
                    'Tamatkan selepas aktiviti berakhir pada ${malaysiaTime(r.endsAt)} MYT.',
                  ),
                ),
              ),
            EmasButton(
              label: c.t('Finish session', 'Tamatkan sesi'),
              onPressed: pending || !finishAllowed
                  ? null
                  : () => action('finish'),
            ),
          ],
          if ((helper || elder) && r.state == RequestState.awaitingConfirmation)
            EmasButton(
              label: (elder ? r.elderConfirmed : r.helperConfirmed)
                  ? c.t('You have confirmed', 'Anda telah mengesahkan')
                  : c.t('Confirm my participation', 'Sahkan penyertaan saya'),
              onPressed:
                  pending || (elder ? r.elderConfirmed : r.helperConfirmed)
                  ? null
                  : () => action('confirm'),
            ),
          PendingSessionAction(name),
          if (r.cancellable &&
              (elder ||
                  c.role == AppRole.coordinator ||
                  (c.role == AppRole.family &&
                      c.session!.selectedElder?.booking == true)))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: pending
                    ? null
                    : () async {
                        final token = scopeToken(c);
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (dialog) => CommunitySheetGuard(
                            token: token,
                            child: AlertDialog(
                              title: Text(
                                c.t(
                                  'Cancel this request?',
                                  'Batal permintaan ini?',
                                ),
                              ),
                              content: Text(
                                c.t(
                                  'The companion’s reserved time will be released. You can make a new request later.',
                                  'Masa teman yang ditempah akan dilepaskan. Anda boleh membuat permintaan baharu kemudian.',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog, false),
                                  child: Text(
                                    c.t('Keep request', 'Kekalkan permintaan'),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog, true),
                                  child: Text(
                                    c.t('Cancel request', 'Batal permintaan'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (context.mounted &&
                            yes == true &&
                            scopeToken(c) == token &&
                            w.request(r.id)?.cancellable == true) {
                          await action('cancel');
                        }
                      },
                child: Text(c.t('Cancel request', 'Batal permintaan')),
              ),
            ),
        ],
      ),
    );
  }
}

class _LiveTimeline extends StatelessWidget {
  const _LiveTimeline(this.state);
  final RequestState state;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    if (state == RequestState.cancelled) return const SizedBox.shrink();
    final current = switch (state) {
      RequestState.requested => 0,
      RequestState.assigned => 1,
      RequestState.accepted || RequestState.inProgress => 2,
      _ => 3,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: Semantics(
              label:
                  '${[c.t("Request", "Permintaan"), c.t("Companion", "Teman"), c.t("Session", "Sesi"), c.t("Both confirm", "Kedua-duanya sahkan")][i]}: ${i < current || state == RequestState.completed
                      ? c.t("done", "selesai")
                      : i == current
                      ? c.t("current", "semasa")
                      : c.t("upcoming", "akan datang")}',
              child: Column(
                children: [
                  Icon(
                    i < current || state == RequestState.completed
                        ? Icons.check_circle
                        : i == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 19,
                    color: i <= current ? Palette.green : Palette.line,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    [
                      c.t('Request', 'Permintaan'),
                      c.t('Companion', 'Teman'),
                      c.t('Session', 'Sesi'),
                      c.t('Both confirm', 'Kedua-duanya sahkan'),
                    ][i],
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AssignmentSheet extends StatefulWidget {
  const _AssignmentSheet(this.requestId);
  final String requestId;
  @override
  State<_AssignmentSheet> createState() => _AssignmentSheetState();
}

class _AssignmentSheetState extends State<_AssignmentSheet> {
  String? selected;
  void _done() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    sessionToast(context, 'Companion assigned.', 'Teman ditetapkan.');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.sessions!;
    final r = w.request(widget.requestId);
    if (w.error != null) {
      return CommunityError(w.error!.message(c.malay), retry: w.retry);
    }
    if (r == null && w.busy('request:${widget.requestId}')) {
      return PendingSessionAction(
        'request:${widget.requestId}',
        onSuccess: _done,
      );
    }
    if (r == null || r.state != RequestState.requested) {
      return CommunityError(
        c.t(
          'This request has changed. Close this sheet to see the latest queue.',
          'Permintaan ini telah berubah. Tutup paparan untuk melihat senarai terkini.',
        ),
      );
    }
    final name = 'request:${r.id}',
        pending = w.actions['request:${r.id}'] != null;
    final pairs =
        c.community?.pairings
            .where(
              (p) =>
                  p.elderId == r.elderId &&
                  p.townshipId == r.townshipId &&
                  p.accepted,
            )
            .toList() ??
        <PairingRecord>[];
    if (!pairs.any((p) => p.id == selected)) selected = pairs.firstOrNull?.id;
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
        const SizedBox(height: 12),
        Text('${r.elderName} · ${sessionWhen(r.startsAt, r.endsAt, c.malay)}'),
        const SizedBox(height: 14),
        Text(
          c.t(
            'Choose an accepted regular pairing. Availability, preferences and the full schedule are checked when you assign.',
            'Pilih pasangan tetap yang diterima. Ketersediaan, pilihan dan jadual penuh disemak semasa penugasan.',
          ),
          style: const TextStyle(color: Palette.muted),
        ),
        const SizedBox(height: 20),
        if (c.community?.catalogError != null)
          CommunityError(
            c.community!.catalogError!.message(c.malay),
            retry: c.community!.retry,
          )
        else if (c.community?.pairingLoading == true)
          const LinearProgressIndicator()
        else if (pairs.isEmpty)
          Text(
            c.t(
              'No accepted regular pairing is available for this elder.',
              'Tiada pasangan tetap yang diterima untuk warga emas ini.',
            ),
          )
        else ...[
          DropdownButtonFormField<String>(
            key: ValueKey('pairing-$selected'),
            initialValue: selected,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: c.t('Regular pairing', 'Pasangan tetap'),
            ),
            items: [
              for (final p in pairs)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(p.helperId, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: pending ? null : (v) => setState(() => selected = v),
          ),
          const SizedBox(height: 14),
          for (final p in pairs.where((p) => p.id == selected))
            Text(
              c.t(
                'Accepted by both · Trial: ${p.trialStartsOn ?? "—"} to ${p.trialEndsOn ?? "—"}',
                'Diterima kedua-duanya · Percubaan: ${p.trialStartsOn ?? "—"} hingga ${p.trialEndsOn ?? "—"}',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 22),
          EmasButton(
            key: const ValueKey('assign-live-companion'),
            label: c.t('Assign companion', 'Tetapkan teman'),
            onPressed: pending || selected == null
                ? null
                : () async {
                    final saved = await w.run(name, 'assign', {
                      'requestId': r.id,
                      'pairingId': selected,
                    });
                    if (mounted && saved) _done();
                  },
          ),
        ],
        PendingSessionAction(name, onSuccess: _done),
      ],
    );
  }
}

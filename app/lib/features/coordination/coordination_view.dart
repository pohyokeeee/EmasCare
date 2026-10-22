import 'package:flutter/material.dart';
import '../../app/app_shell.dart';
import '../../app/preview_controller.dart';
import '../../models/backend_models.dart';
import '../../models/community_models.dart';
import '../../models/coordination_models.dart';
import '../../models/preview_models.dart';
import '../../shared/design_system.dart';
import '../community/community_ui.dart';
import '../community/request_form.dart';
import '../community/session_ui.dart';
import '../wallet/wallet_view.dart';
import 'voice_booking_view.dart';
import 'coordination_review.dart';

void openCoordination(BuildContext context, {String section = 'updates'}) {
  final c = PreviewScope.of(context), w = c.coordination!;
  w.refresh();
  showEmasSheet(
    context,
    CoordinationGuard(
      token: w.viewToken,
      child: CoordinationPanel(initial: section),
    ),
  );
}

class CoordinationGuard extends StatelessWidget {
  const CoordinationGuard({
    super.key,
    required this.token,
    required this.child,
  });
  final String? token;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (token != null &&
        PreviewScope.of(context).coordination?.viewToken == token) {
      return child;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
      }
    });
    return const SizedBox.shrink();
  }
}

class CoordinationEntry extends StatelessWidget {
  const CoordinationEntry({super.key});
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.coordination;
    if (w == null) return const SizedBox.shrink();
    final unread = w.notices.where((n) => n.readAt == null).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('stage6-updates'),
            onPressed: () => openCoordination(context),
            icon: const Icon(Icons.notifications_none),
            label: Text(
              c.t(
                'Updates${unread > 0 ? ' ($unread)' : ''}',
                'Kemas kini${unread > 0 ? ' ($unread)' : ''}',
              ),
            ),
          ),
          OutlinedButton.icon(
            key: const ValueKey('stage6-progress'),
            onPressed: () => openCoordination(context, section: 'progress'),
            icon: const Icon(Icons.trending_up),
            label: Text(c.t('Progress & community', 'Kemajuan & komuniti')),
          ),
          OutlinedButton.icon(
            key: const ValueKey('stage6-reports'),
            onPressed: () => openCoordination(context, section: 'reports'),
            icon: const Icon(Icons.flag_outlined),
            label: Text(c.t('Reports & places', 'Laporan & tempat')),
          ),
          if (c.role == AppRole.coordinator)
            OutlinedButton.icon(
              key: const ValueKey('stage6-operations'),
              onPressed: () => openCoordination(context, section: 'operations'),
              icon: const Icon(Icons.dashboard_outlined),
              label: Text(c.t('Coordinator tools', 'Alat penyelaras')),
            ),
          if (w.mayBook && c.destination == Destination.companion)
            OutlinedButton.icon(
              key: const ValueKey('stage6-voice'),
              onPressed: () {
                w.clearVoice();
                showEmasSheet(
                  context,
                  CoordinationGuard(
                    token: w.viewToken,
                    child: VoiceBookingView(
                      onManual: () {
                        Navigator.pop(context);
                        openCompanionRequest(context);
                      },
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.mic_none),
              label: Text(c.t('Voice / text booking', 'Tempahan suara / teks')),
            ),
          if (w.actions.isNotEmpty)
            TextButton(
              onPressed: () => openCoordination(context),
              child: Text(
                c.t('Action awaiting a response', 'Tindakan menunggu jawapan'),
              ),
            ),
        ],
      ),
    );
  }
}

class CoordinationPanel extends StatefulWidget {
  const CoordinationPanel({super.key, this.initial = 'updates'});
  final String initial;
  @override
  State<CoordinationPanel> createState() => _CoordinationPanelState();
}

class _CoordinationPanelState extends State<CoordinationPanel> {
  late String selected = widget.initial;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.coordination!;
    final tabs = {
      'updates': c.t('Updates', 'Kemas kini'),
      'progress': c.t('Progress', 'Kemajuan'),
      'reports': c.t('Reports & places', 'Laporan & tempat'),
      if (c.role == AppRole.coordinator)
        'operations': c.t('Operations', 'Operasi'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommunityHeading(
          c.t('A connected community.', 'Komuniti yang terhubung.'),
          c.t(
            'Saved updates, shared progress and a little support.',
            'Kemas kini tersimpan, kemajuan bersama dan sedikit sokongan.',
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in tabs.entries)
              ChoiceChip(
                label: Text(t.value),
                selected: selected == t.key,
                onSelected: (_) => setState(() => selected = t.key),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: w.refresh,
            icon: const Icon(Icons.refresh),
            label: Text(
              c.t(
                'Refresh saved information',
                'Muat semula maklumat tersimpan',
              ),
            ),
          ),
        ),
        if (w.errors['access'] != null)
          CommunityError(w.errors['access']!.message(c.malay), retry: w.retry),
        for (final id in w.actions.keys.toList()) PendingCoordinationAction(id),
        const SizedBox(height: 12),
        if (selected == 'updates') const _Updates(),
        if (selected == 'progress') const _Progress(),
        if (selected == 'reports') const _ReportsAndPlaces(),
        if (selected == 'operations' && c.role == AppRole.coordinator)
          const _Operations(),
      ],
    );
  }
}

class PendingCoordinationAction extends StatelessWidget {
  const PendingCoordinationAction(this.id, {super.key, this.onSuccess});
  final String id;
  final VoidCallback? onSuccess;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.coordination!, a = w.actions[id];
    if (a == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Semantics(
        liveRegion: true,
        child: Surface(
          color: Palette.sand,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (a.busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 10),
                Text(c.t('Saving your action…', 'Menyimpan tindakan anda…')),
              ] else ...[
                Text(
                  a.error?.message(c.malay) ??
                      c.t('Ready to retry.', 'Sedia untuk dicuba semula.'),
                ),
                const SizedBox(height: 10),
                Text(
                  c.t(
                    'Retry uses the same confirmed details and action.',
                    'Cubaan semula menggunakan butiran dan tindakan disahkan yang sama.',
                  ),
                ),
                const SizedBox(height: 14),
                EmasButton(
                  label: c.t('Retry saved action', 'Cuba semula tindakan'),
                  secondary: true,
                  onPressed: () async {
                    if (await w.retryAction(id)) onSuccess?.call();
                  },
                ),
                TextButton(
                  onPressed: () => w.discard(id),
                  child: Text(
                    c.t(
                      'Stop retrying / choose again',
                      'Hentikan cubaan / pilih semula',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String noticeLabel(String kind, bool bm) => switch (kind) {
  'checkin_reminder' => bm ? 'Masa untuk Saya OK' : 'Time for Saya OK',
  'checkin_missed' =>
    bm ? 'Daftar masuk perlu susulan' : 'Check-in needs follow-up',
  'request_updated' =>
    bm ? 'Permintaan teman dikemas kini' : 'Companion request updated',
  'attendance_review' => bm ? 'Kehadiran telah disemak' : 'Attendance reviewed',
  'family_cheer' =>
    bm ? 'Keluarga memberi semangat' : 'A cheer from your family',
  _ => bm ? 'Kemas kini komuniti' : 'Community update',
};

class _Updates extends StatelessWidget {
  const _Updates();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.coordination!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          c.t(
            'In-app updates only. Check-in follow-up runs when a coordinator starts it; no push delivery is claimed.',
            'Kemas kini dalam aplikasi sahaja. Susulan daftar masuk dijalankan oleh penyelaras; tiada penghantaran push.',
          ),
        ),
        if (c.role == AppRole.family && !w.mayShare)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              c.t(
                'Daily sharing is off. Booking updates follow the separate booking permission.',
                'Perkongsian harian tidak aktif. Kemas kini tempahan mengikut kebenaran tempahan berasingan.',
              ),
            ),
          ),
        for (final e in w.errors.entries.where(
          (e) => e.key.startsWith('notices:'),
        ))
          CommunityError(e.value.message(c.malay), retry: w.retry),
        if (w.notices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              c.t(
                'No permitted updates yet.',
                'Belum ada kemas kini yang dibenarkan.',
              ),
            ),
          ),
        for (final n in w.notices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    noticeLabel(n.kind, c.malay),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(whenLabel(n.createdAt, c.malay)),
                  if (n.messageParams['state'] is String)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _stateLabel(
                          n.messageParams['state'] as String,
                          c.malay,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  EmasButton(
                    key: ValueKey('read-notice-${n.id}'),
                    label: n.readAt == null
                        ? c.t('Mark as read', 'Tandakan dibaca')
                        : c.t('Read', 'Dibaca'),
                    secondary: true,
                    onPressed: n.readAt != null
                        ? null
                        : () async {
                            await w.run(
                              'notice:${n.id}',
                              'markNotificationRead',
                              {'notificationId': n.id},
                            );
                          },
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

String _stateLabel(String state, bool bm) => switch (state) {
  'new' => bm ? 'Baharu' : 'New',
  'seen' => bm ? 'Dalam semakan' : 'Seen',
  'done' => bm ? 'Selesai' : 'Done',
  'verified' => bm ? 'Disahkan' : 'Verified',
  'rejected' => bm ? 'Ditolak' : 'Rejected',
  'completed' => bm ? 'Selesai' : 'Completed',
  'requested' => bm ? 'Diminta' : 'Requested',
  'assigned' => bm ? 'Ditugaskan' : 'Assigned',
  'accepted' => bm ? 'Diterima' : 'Accepted',
  'in_progress' => bm ? 'Sedang berjalan' : 'In progress',
  'awaiting_confirmation' =>
    bm ? 'Menunggu pengesahan' : 'Awaiting confirmation',
  'cancelled' => bm ? 'Dibatalkan' : 'Cancelled',
  'pending' => bm ? 'Menunggu' : 'Pending',
  'reminded' => bm ? 'Perlu daftar masuk' : 'Due',
  'missed' => bm ? 'Lewat' : 'Overdue',
  'ok' => bm ? 'Saya OK diterima' : 'Saya OK received',
  'paused' => bm ? 'Dijeda' : 'Paused',
  'notMaterialized' => bm ? 'Belum dijana' : 'Not yet generated',
  'submitted' => bm ? 'Dihantar' : 'Submitted',
  'active' => bm ? 'Aktif' : 'Active',
  'needsReview' => bm ? 'Perlu semakan' : 'Needs review',
  _ => bm ? 'Kemas kini direkod' : 'Update recorded',
};

class _Progress extends StatelessWidget {
  const _Progress();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.coordination!;
    final labels = {
      'elder': c.t('Outings together', 'Keluar bersama'),
      'helper': c.t('Your volunteering', 'Sukarelawan anda'),
      'household': c.t('Household give-back', 'Sumbangan isi rumah'),
      'township': c.t('Community progress', 'Kemajuan komuniti'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final p in ['week', 'month'])
              ChoiceChip(
                label: Text(
                  p == 'week'
                      ? c.t('This week', 'Minggu ini')
                      : c.t('This month', 'Bulan ini'),
                ),
                selected: w.periodType == p,
                onSelected: (_) => w.selectPeriod(p),
              ),
          ],
        ),
        if (c.role == AppRole.family && !w.mayShare)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              c.t(
                'Your elder’s outing progress is private while sharing is off.',
                'Kemajuan keluar warga emas adalah peribadi apabila perkongsian tidak aktif.',
              ),
            ),
          ),
        if (c.role == AppRole.coordinator && w.elderProfiles.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: w.selectedCoordinatorElder,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: c.t('Resident progress', 'Kemajuan penduduk'),
            ),
            items: [
              for (final e in w.elderProfiles)
                DropdownMenuItem(
                  value: e['id'] as String,
                  child: Text(e['displayName'] as String),
                ),
            ],
            onChanged: (id) {
              if (id != null) w.selectElder(id);
            },
          ),
        for (final scope in labels.keys) ...[
          if (w.loading.contains('progress:$scope'))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
          if (w.errors['progress:$scope'] != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: CommunityError(
                w.errors['progress:$scope']!.message(c.malay),
                retry: w.refresh,
              ),
            ),
          if (w.progress[scope] != null)
            _ProgressCard(labels[scope]!, w.progress[scope]!),
        ],
        const SizedBox(height: 18),
        const _Availability(),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard(this.title, this.record);
  final String title;
  final ProgressRecord record;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.coordination!, r = record;
    final metric = r.scope == 'elder' || r.scope == 'township'
        ? 'outings'
        : r.scope == 'helper'
        ? 'helpingSessions'
        : 'weekendGiveBack';
    final amount = r.counts[metric]!, target = r.targets[metric];
    // Household/township summaries never authorize an individual outing or cheer.
    final latest = r.scope == 'elder' ? r.latestOuting : null;
    final already =
        latest != null &&
        w.cheers.any(
          (e) =>
              e['participationId'] == latest['participationId'] &&
              e['familyUid'] == c.session!.profile!.uid,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Surface(
        color: Palette.soft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(
              target == null ? '$amount' : '$amount / $target',
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w600,
                color: Palette.green,
              ),
            ),
            if (target != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: (amount / target).clamp(0, 1)),
            ],
            const SizedBox(height: 12),
            Text(
              r.scope == 'elder' || r.scope == 'township'
                  ? c.t('Verified outings', 'Keluar yang disahkan')
                  : r.scope == 'helper'
                  ? c.t('Completed helping sessions', 'Sesi bantuan selesai')
                  : c.t(
                      'Weekend helping sessions',
                      'Sesi bantuan hujung minggu',
                    ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (r.isDemo)
                  Pill(c.t('Local demo goals', 'Sasaran demo setempat')),
                if (r.includesSeededHistory)
                  Pill(
                    c.t(
                      'Includes illustrative history',
                      'Termasuk sejarah contoh',
                    ),
                    gold: true,
                  ),
              ],
            ),
            if (r.pendingClassifications > 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  c.t(
                    '${r.pendingClassifications} sitting/carrying participations await an outing definition. Rewards are separate.',
                    '${r.pendingClassifications} penyertaan duduk/membawa menunggu takrif keluar. Ganjaran adalah berasingan.',
                  ),
                ),
              ),
            if (latest != null) ...[
              const SizedBox(height: 14),
              Text(
                localizedRecord(latest['activityTitle']).inLanguage(c.malay),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(whenLabel(utcTimestamp(latest['completedAt'])!, c.malay)),
              if (c.role == AppRole.family && w.mayShare) ...[
                const SizedBox(height: 14),
                EmasButton(
                  key: const ValueKey('family-cheer'),
                  label:
                      w.actions['cheer:${latest['participationId']}']?.busy ==
                          true
                      ? c.t('Sending cheer…', 'Menghantar semangat…')
                      : already
                      ? c.t('Cheer sent', 'Semangat dihantar')
                      : c.t('Send a family cheer', 'Beri semangat keluarga'),
                  icon: Icons.favorite_border,
                  onPressed:
                      already ||
                          w
                                  .actions['cheer:${latest['participationId']}']
                                  ?.busy ==
                              true
                      ? null
                      : () async {
                          await w.run(
                            'cheer:${latest['participationId']}',
                            'sendFamilyCheer',
                            {'participationId': latest['participationId']},
                          );
                        },
                ),
              ],
            ],
            if (r.scope == 'elder')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  c.t(
                    '${w.cheers.length} family cheers · no extra coins',
                    '${w.cheers.length} sokongan keluarga · tiada syiling tambahan',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Availability extends StatelessWidget {
  const _Availability();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context),
        w = c.coordination!,
        data = w.availability;
    if (w.errors['availability'] != null) {
      return CommunityError(
        w.errors['availability']!.message(c.malay),
        retry: w.refresh,
      );
    }
    if (data == null) return const LinearProgressIndicator();
    final days = c.malay
        ? ['Isn', 'Sel', 'Rab', 'Kha', 'Jum', 'Sab', 'Ahd']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    String time(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          c.t('Community availability', 'Ketersediaan komuniti'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(
          c.t(
            'Illustrative demo groups, not bookable helpers. Small groups are hidden for privacy.',
            'Kumpulan contoh demo, bukan pembantu untuk ditempah. Kumpulan kecil disembunyikan demi privasi.',
          ),
        ),
        for (final raw in data['cells'] as List)
          Builder(
            builder: (_) {
              final cell = jsonObject(raw);
              final cohort = switch (cell['cohort']) {
                'student' => c.t('Students', 'Pelajar'),
                'retiree' => c.t('Retirees', 'Pesara'),
                _ => c.t('Working adults', 'Orang bekerja'),
              };
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$cohort · ${days[(cell['weekday'] as int) - 1]}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${time(cell['startMinute'])}–${time(cell['endMinute'])} MYT',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        cell['suppressed'] == true
                            ? c.t(
                                'Counts hidden: fewer than five helpers.',
                                'Bilangan disembunyikan: kurang daripada lima pembantu.',
                              )
                            : c.t(
                                '${cell['helperCount']} demo helpers · ${cell['requestCount']} demo requests',
                                '${cell['helperCount']} pembantu demo · ${cell['requestCount']} permintaan demo',
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

void openCoordinationForm(
  BuildContext context,
  String kind, {
  String? placeId,
}) {
  final w = PreviewScope.of(context).coordination!;
  showEmasSheet(
    context,
    CoordinationGuard(
      token: w.viewToken,
      child: CoordinationForm(kind: kind, placeId: placeId),
    ),
  );
}

class _ReportsAndPlaces extends StatelessWidget {
  const _ReportsAndPlaces();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context),
        w = c.coordination!,
        coordinator = c.role == AppRole.coordinator;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EmasButton(
          key: const ValueKey('submit-report'),
          label: c.t('Report a problem', 'Laporkan masalah'),
          icon: Icons.flag_outlined,
          onPressed: () => openCoordinationForm(context, 'submitReport'),
        ),
        const SizedBox(height: 20),
        Text(
          coordinator
              ? c.t('Township reports', 'Laporan perbandaran')
              : c.t('Your saved reports', 'Laporan tersimpan anda'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        for (final e in w.errors.entries.where(
          (e) => e.key.startsWith('reports:'),
        ))
          CommunityError(e.value.message(c.malay), retry: w.retry),
        if (w.reports.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              c.t(
                'No permitted reports yet.',
                'Belum ada laporan yang dibenarkan.',
              ),
            ),
          ),
        for (final r in w.reports)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Pill(_stateLabel(r.state, c.malay)),
                  ),
                  const SizedBox(height: 12),
                  Text(r.text),
                  const SizedBox(height: 10),
                  Text(
                    whenLabel(r.createdAt, c.malay),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (coordinator && r.state != 'done') ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (r.state == 'new')
                          OutlinedButton(
                            onPressed: w.actions['review:${r.id}']?.busy == true
                                ? null
                                : () async {
                                    await w.run(
                                      'review:${r.id}',
                                      'reviewReport',
                                      {'reportId': r.id, 'state': 'seen'},
                                    );
                                  },
                            child: Text(c.t('Mark seen', 'Tandakan dilihat')),
                          ),
                        OutlinedButton(
                          onPressed: w.actions['review:${r.id}']?.busy == true
                              ? null
                              : () async {
                                  await w.run(
                                    'review:${r.id}',
                                    'reviewReport',
                                    {'reportId': r.id, 'state': 'done'},
                                  );
                                },
                          child: Text(c.t('Mark done', 'Tandakan selesai')),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 24),
        Text(
          c.t('Place warnings', 'Amaran tempat'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (c.role == AppRole.elder) ...[
          const SizedBox(height: 14),
          EmasButton(
            label: c.t('Block my companion', 'Sekat teman saya'),
            secondary: true,
            onPressed: () => openCoordinationForm(context, 'blockHelper'),
          ),
        ],
        for (final p in c.community?.places ?? <PlaceRecord>[])
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(p.name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  if (p.notice != null) ...[
                    Pill(
                      p.notice!.activeAt(c.session!.clock())
                          ? c.t('Recorded warning', 'Amaran direkodkan')
                          : c.t(
                              'Needs coordinator review',
                              'Perlu semakan penyelaras',
                            ),
                      gold: true,
                    ),
                    const SizedBox(height: 10),
                    Text(p.notice!.text.inLanguage(c.malay)),
                    if (!p.notice!.activeAt(c.session!.clock()))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          c.t(
                            'Expiry does not mean the place is safe. The warning stays until reviewed.',
                            'Tamat tempoh tidak bermakna tempat selamat. Amaran kekal sehingga disemak.',
                          ),
                        ),
                      ),
                  ] else
                    Text(
                      c.t(
                        'No warning recorded. Check current conditions.',
                        'Tiada amaran direkodkan. Semak keadaan semasa.',
                      ),
                    ),
                  if (coordinator) ...[
                    const SizedBox(height: 14),
                    EmasButton(
                      label: c.t(
                        'Review / update warning',
                        'Semak / kemas kini amaran',
                      ),
                      secondary: true,
                      onPressed: () => openCoordinationForm(
                        context,
                        'setPlaceWarning',
                        placeId: p.id,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Operations extends StatelessWidget {
  const _Operations();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context),
        w = c.coordination!,
        summary = w.summary;
    final names = {
      'checkins': c.t('Today’s check-ins', 'Daftar masuk hari ini'),
      'requests': c.t('Companion requests', 'Permintaan teman'),
      'attendance': c.t('Attendance', 'Kehadiran'),
      'reports': c.t('Reports', 'Laporan'),
      'placeWarnings': c.t('Place warnings', 'Amaran tempat'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (w.loading.contains('summary')) const LinearProgressIndicator(),
        if (w.errors['summary'] != null)
          CommunityError(
            w.errors['summary']!.message(c.malay),
            retry: w.refresh,
          ),
        if (summary != null)
          for (final section in names.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      section.value,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final value in jsonObject(
                          summary[section.key],
                        ).entries)
                          Pill(
                            '${_stateLabel(value.key, c.malay)} · ${value.value}',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 16),
        Text(
          c.t('Run check-in follow-up', 'Jalankan susulan daftar masuk'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(
          c.t(
            'Create due reminders and missed-check-in records now. This is a manual demo process, not a background scheduler or phone call. Expired warnings stay for review.',
            'Jana peringatan dan rekod daftar masuk lewat sekarang. Ini proses demo manual, bukan penjadual latar atau panggilan telefon. Amaran tamat tempoh kekal untuk semakan.',
          ),
        ),
        const SizedBox(height: 16),
        EmasButton(
          key: const ValueKey('process-due-items'),
          label: w.actions['due']?.busy == true
              ? c.t('Processing check-ins…', 'Memproses daftar masuk…')
              : c.t(
                  'Process due check-ins now',
                  'Proses daftar masuk perlu tindakan',
                ),
          onPressed: w.actions['due']?.busy == true
              ? null
              : () async {
                  await w.run('due', 'processDemoDueItems', {});
                },
        ),
        if (w.dueResult != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              c.t(
                '${w.dueResult!['remindersCreated']} reminders and ${w.dueResult!['missedAlertsCreated']} missed notices created in the app.',
                '${w.dueResult!['remindersCreated']} peringatan dan ${w.dueResult!['missedAlertsCreated']} notis lewat dijana dalam aplikasi.',
              ),
            ),
          ),
        const SizedBox(height: 24),
        EmasButton(
          key: const ValueKey('block-helper'),
          label: c.t(
            'Block a helper for a resident',
            'Sekat pembantu untuk penduduk',
          ),
          secondary: true,
          onPressed: () => openCoordinationForm(context, 'blockHelper'),
        ),
        for (final b in w.blocks)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Surface(
              child: Text(
                c.t(
                  'Future helper assignments blocked. ${b['reason']}',
                  'Penugasan pembantu akan datang disekat. ${b['reason']}',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class CoordinationForm extends StatefulWidget {
  const CoordinationForm({super.key, required this.kind, this.placeId});
  final String kind;
  final String? placeId;
  @override
  State<CoordinationForm> createState() => _CoordinationFormState();
}

class _CoordinationFormState extends State<CoordinationForm> {
  final text = TextEditingController(), expiry = TextEditingController();
  String? place, request, pair;
  String reportKind = 'place_problem', warningLevel = 'warning', intent = '';
  Json? confirmed;
  String? validation;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (intent.isNotEmpty) return;
    final c = PreviewScope.of(context);
    intent = c.coordination!.nextIntent();
    place = widget.placeId ?? c.community?.places.firstOrNull?.id;
    final later = c.session!.clock().add(const Duration(hours: 2));
    expiry.text = '${malaysiaDate(later)} ${malaysiaTime(later)}';
    pair = c.community?.pairings.firstOrNull?.id;
  }

  @override
  void dispose() {
    text.dispose();
    expiry.dispose();
    super.dispose();
  }

  void done() {
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.pop(context);
    }
  }

  void prepare() {
    final c = PreviewScope.of(context), value = text.text.trim();
    final requestRecord = c.sessions?.requests
        .where((r) => r.id == request)
        .firstOrNull;
    final pairing = c.community?.pairings
        .where((p) => p.id == pair)
        .firstOrNull;
    if (value.isEmpty ||
        value.length >
            (widget.kind == 'setPlaceWarning'
                ? 300
                : widget.kind == 'blockHelper'
                ? 500
                : 1000)) {
      setState(
        () => validation = c.t(
          'Enter a short description within the limit.',
          'Masukkan penerangan ringkas dalam had.',
        ),
      );
      return;
    }
    Json fields;
    if (widget.kind == 'setPlaceWarning') {
      final localText = expiry.text.trim();
      final at = DateTime.tryParse(
        '${localText.replaceFirst(' ', 'T')}:00+08:00',
      );
      final normalized = at
          ?.toUtc()
          .add(const Duration(hours: 8))
          .toIso8601String()
          .substring(0, 16)
          .replaceFirst('T', ' ');
      if (place == null ||
          !RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(localText) ||
          at == null ||
          normalized != localText ||
          !at.isAfter(c.session!.clock())) {
        setState(
          () => validation = c.t(
            'Choose a place and a future expiry.',
            'Pilih tempat dan masa tamat akan datang.',
          ),
        );
        return;
      }
      fields = {
        'placeId': place,
        'warning': {
          'level': warningLevel,
          'text': value,
          'expiresAt': at.toUtc().toIso8601String(),
        },
      };
    } else if (widget.kind == 'blockHelper') {
      if (pairing == null) {
        setState(
          () => validation = c.t(
            'Choose an existing companion pairing.',
            'Pilih pasangan teman sedia ada.',
          ),
        );
        return;
      }
      fields = {
        'elderId': pairing.elderId,
        'helperId': pairing.helperId,
        'reason': value,
      };
    } else {
      if (reportKind == 'helper_report' && requestRecord?.helperId == null ||
          reportKind == 'place_problem' && place == null) {
        setState(
          () => validation = c.t(
            'Choose the relevant place or assigned session.',
            'Pilih tempat atau sesi ditugaskan yang berkaitan.',
          ),
        );
        return;
      }
      fields = {
        'kind': reportKind,
        'text': value,
        'placeId': reportKind == 'place_problem' ? place : null,
        'requestId': reportKind == 'helper_report' ? request : null,
        'helperId': reportKind == 'helper_report'
            ? requestRecord!.helperId
            : null,
      };
    }
    setState(() {
      confirmed = fields;
      validation = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.coordination!, kind = widget.kind;
    final title = kind == 'setPlaceWarning'
        ? c.t('Review a place warning', 'Semak amaran tempat')
        : kind == 'blockHelper'
        ? c.t('Block a companion', 'Sekat teman')
        : c.t('Report a problem', 'Laporkan masalah');
    final pending = w.actions[intent];
    final other = w.actions.entries
        .where((e) => e.key != intent && e.value.kind == kind)
        .firstOrNull;
    if (other != null) {
      return Column(
        children: [
          Text(
            c.t(
              'Resolve your saved action first.',
              'Selesaikan tindakan tersimpan dahulu.',
            ),
          ),
          PendingCoordinationAction(other.key),
        ],
      );
    }
    if (confirmed != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            c.t('Review before saving', 'Semak sebelum menyimpan'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Text(title),
          const SizedBox(height: 12),
          CoordinationReview(kind: kind, fields: confirmed!),
          const SizedBox(height: 16),
          Text(
            kind == 'setPlaceWarning' && confirmed!['warning'] == null
                ? c.t(
                    'Clear the recorded warning after review.',
                    'Kosongkan amaran direkodkan selepas semakan.',
                  )
                : text.text,
          ),
          if (kind == 'blockHelper')
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                c.t(
                  'Blocks future assignment, acceptance and starting for this elder. Existing bookings are not cancelled. A coordinator must follow up; there is no unblock button.',
                  'Menyekat penugasan, penerimaan dan permulaan akan datang untuk warga emas ini. Tempahan sedia ada tidak dibatalkan. Penyelaras perlu membuat susulan; tiada butang nyahsekat.',
                ),
              ),
            ),
          const SizedBox(height: 20),
          EmasButton(
            key: const ValueKey('confirm-coordination-action'),
            label: c.t('Confirm and save', 'Sahkan dan simpan'),
            onPressed: pending != null
                ? null
                : () async {
                    if (await w.run(intent, kind, confirmed!)) done();
                  },
          ),
          PendingCoordinationAction(intent, onSuccess: done),
          TextButton(
            onPressed: pending != null
                ? null
                : () => setState(() => confirmed = null),
            child: Text(c.t('Edit details', 'Edit butiran')),
          ),
        ],
      );
    }
    final places = c.community?.places ?? <PlaceRecord>[];
    final helperRequests =
        c.sessions?.requests.where((r) => r.helperId != null).toList() ?? [];
    final pairings = c.community?.pairings ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 18),
        if (kind == 'submitReport')
          DropdownButtonFormField<String>(
            initialValue: reportKind,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: c.t('What happened?', 'Apa yang berlaku?'),
            ),
            items: [
              DropdownMenuItem(
                value: 'place_problem',
                child: Text(
                  c.t('Place access problem', 'Masalah akses tempat'),
                ),
              ),
              if (helperRequests.isNotEmpty)
                DropdownMenuItem(
                  value: 'helper_report',
                  child: Text(
                    c.t('Companion session concern', 'Kebimbangan sesi teman'),
                  ),
                ),
            ],
            onChanged: (v) => setState(() => reportKind = v!),
          ),
        const SizedBox(height: 12),
        if (kind == 'setPlaceWarning' ||
            kind == 'submitReport' && reportKind == 'place_problem')
          DropdownButtonFormField<String>(
            initialValue: place,
            isExpanded: true,
            decoration: InputDecoration(labelText: c.t('Place', 'Tempat')),
            items: [
              for (final p in places)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: (v) => setState(() => place = v),
          ),
        if (kind == 'submitReport' && reportKind == 'helper_report')
          DropdownButtonFormField<String>(
            initialValue: request,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: c.t('Assigned session', 'Sesi ditugaskan'),
            ),
            items: [
              for (final r in helperRequests)
                DropdownMenuItem(
                  value: r.id,
                  child: Text(
                    '${r.elderName} · ${sessionTask(r.taskType, c.malay)} · ${malaysiaDate(r.startsAt)}',
                  ),
                ),
            ],
            onChanged: (v) => setState(() => request = v),
          ),
        if (kind == 'blockHelper') ...[
          DropdownButtonFormField<String>(
            initialValue: pair,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: c.t('Companion pairing', 'Pasangan teman'),
            ),
            items: [
              for (final p in pairings)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    c.t('Regular companion · ', 'Teman tetap · ') +
                        (w.elderProfiles
                                    .where((e) => e['id'] == p.elderId)
                                    .firstOrNull?['displayName']
                                as String? ??
                            c.session!.profile!.displayName),
                  ),
                ),
            ],
            onChanged: (v) => setState(() => pair = v),
          ),
          if (pairings.isEmpty)
            Text(
              c.t(
                'No recorded pairing is available.',
                'Tiada pasangan direkodkan tersedia.',
              ),
            ),
        ],
        if (kind == 'setPlaceWarning') ...[
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: warningLevel,
            decoration: InputDecoration(
              labelText: c.t('Warning level', 'Tahap amaran'),
            ),
            items: [
              DropdownMenuItem(
                value: 'warning',
                child: Text(c.t('Warning', 'Amaran')),
              ),
              DropdownMenuItem(
                value: 'closed',
                child: Text(c.t('Closed', 'Ditutup')),
              ),
            ],
            onChanged: (v) => setState(() => warningLevel = v!),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: expiry,
            decoration: InputDecoration(
              labelText: c.t(
                'Review due (MYT · YYYY-MM-DD HH:mm)',
                'Semakan perlu (MYT · YYYY-MM-DD HH:mm)',
              ),
              helperText: c.t(
                'Example: 2026-10-23 18:00',
                'Contoh: 2026-10-23 18:00',
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: text,
          maxLength: kind == 'setPlaceWarning'
              ? 300
              : kind == 'blockHelper'
              ? 500
              : 1000,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: c.t('Description / reason', 'Penerangan / sebab'),
          ),
        ),
        if (validation != null)
          Text(validation!, style: const TextStyle(color: Palette.gold)),
        const SizedBox(height: 16),
        EmasButton(
          label: c.t('Review details', 'Semak butiran'),
          onPressed: prepare,
        ),
        if (kind == 'setPlaceWarning') ...[
          const SizedBox(height: 16),
          TextButton(
            onPressed: place == null
                ? null
                : () => setState(
                    () => confirmed = {'placeId': place, 'warning': null},
                  ),
            child: Text(
              c.t(
                'Explicitly clear this warning',
                'Kosongkan amaran ini secara nyata',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

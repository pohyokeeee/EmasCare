import 'package:flutter/material.dart';
import '../../app/app_shell.dart';
import '../../app/preview_controller.dart';
import '../../models/attendance_models.dart';
import '../../models/backend_models.dart';
import '../../models/community_models.dart';
import '../../models/preview_models.dart';
import '../../models/session_models.dart';
import '../../shared/design_system.dart';
import 'community_ui.dart';
import 'session_ui.dart';

String attendanceLabel(AttendanceStatus status, bool bm) => switch (status) {
  AttendanceStatus.submitted =>
    bm ? 'Menunggu pengesahan' : 'Awaiting verification',
  AttendanceStatus.verified =>
    bm ? 'Kehadiran disahkan' : 'Verified attendance',
  AttendanceStatus.rejected => bm ? 'Tidak disahkan' : 'Not verified',
};

class AttendanceSheetGuard extends StatelessWidget {
  const AttendanceSheetGuard({
    super.key,
    required this.token,
    required this.child,
  });
  final String? token;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (token != null &&
        PreviewScope.of(context).attendance?.viewToken == token) {
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

class PendingAttendanceAction extends StatelessWidget {
  const PendingAttendanceAction(this.name, {super.key, this.onSuccess});
  final String name;
  final VoidCallback? onSuccess;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.attendance!;
    final action = w.actions[name];
    if (action == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: action.busy
          ? Column(
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 10),
                Text(c.t('Saving your action…', 'Menyimpan tindakan anda…')),
              ],
            )
          : Surface(
              color: Palette.sand,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      action.error?.message(c.malay) ??
                          c.t('Ready to retry.', 'Sedia untuk dicuba semula.'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    c.t(
                      'Retrying keeps the same attendance and details.',
                      'Cuba semula mengekalkan kehadiran dan butiran yang sama.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  EmasButton(
                    label: c.t('Try again', 'Cuba lagi'),
                    secondary: true,
                    onPressed: () async {
                      final saved = await w.retryAction(name);
                      // A queue row may leave before the callable resolves. The owner
                      // checks its route and mounted state before dismissing.
                      if (saved) onSuccess?.call();
                    },
                  ),
                  TextButton(
                    onPressed: () => w.discard(name),
                    child: Text(
                      c.t(
                        'Stop retrying / review details',
                        'Hentikan cubaan / semak butiran',
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class AttendanceActionPanel extends StatelessWidget {
  const AttendanceActionPanel(this.activity, {super.key});
  final ActivityRecord activity;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.attendance;
    if (w == null || c.role != AppRole.elder) return const SizedBox.shrink();
    if (w.error != null) {
      return CommunityError(w.error!.message(c.malay), retry: w.retry);
    }
    if (w.loading || c.sessions?.loading == true) {
      return const LinearProgressIndicator();
    }
    final record = w.forActivity(activity.id);
    if (record != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: AttendanceRecordCard(record, compact: true),
      );
    }
    final managed =
        c.sessions?.requests.any(
          (r) =>
              r.activityId == activity.id && r.state != RequestState.cancelled,
        ) ==
        true;
    final ended = !activity.endsAt.isAfter(c.community!.now);
    final name = 'submit:${activity.id}',
        pending = w.actions.containsKey('submit:${activity.id}');
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Surface(
        color: Palette.soft,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check_outlined, color: Palette.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    c.t('Were you there?', 'Adakah anda hadir?'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              managed
                  ? c.t(
                      'This activity uses your companion session. Complete both participants’ confirmations in My companion; attendance is recorded there.',
                      'Aktiviti ini menggunakan sesi teman anda. Lengkapkan pengesahan kedua-dua peserta dalam Teman saya; kehadiran direkodkan di sana.',
                    )
                  : activity.participationMode != 'in_person'
                  ? c.t(
                      'Attendance submission is available for in-person activities.',
                      'Penyerahan kehadiran tersedia untuk aktiviti bersemuka.',
                    )
                  : !ended
                  ? c.t(
                      'You can submit attendance after this activity ends. Your coordinator will check it before it is verified.',
                      'Anda boleh menghantar kehadiran selepas aktiviti tamat. Penyelaras akan menyemaknya sebelum disahkan.',
                    )
                  : c.t(
                      'If you attended without a companion session, send your attendance for the coordinator to check. Submission alone is not verified attendance.',
                      'Jika anda hadir tanpa sesi teman, hantar kehadiran untuk disemak penyelaras. Penyerahan sahaja bukan kehadiran yang disahkan.',
                    ),
            ),
            const SizedBox(height: 16),
            if (managed)
              EmasButton(
                label: c.t('Open My companion', 'Buka Teman saya'),
                secondary: true,
                onPressed: () {
                  Navigator.pop(context);
                  c.navigate(destination: Destination.companion);
                },
              )
            else
              EmasButton(
                key: ValueKey('submit-attendance-${activity.id}'),
                label: c.t('I attended', 'Saya hadir'),
                icon: Icons.check,
                onPressed:
                    !ended ||
                        activity.participationMode != 'in_person' ||
                        pending
                    ? null
                    : () async {
                        final saved = await w.submit(activity.id);
                        if (context.mounted && saved) {
                          sessionToast(
                            context,
                            'Attendance sent for verification.',
                            'Kehadiran dihantar untuk pengesahan.',
                          );
                        }
                      },
              ),
            PendingAttendanceAction(name),
          ],
        ),
      ),
    );
  }
}

class AttendanceHistory extends StatelessWidget {
  const AttendanceHistory({super.key});
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.attendance!;
    final family = c.role == AppRole.family;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommunityHeading(
          c.t('Days you took part.', 'Hari anda menyertai.'),
          c.t(
            'Saved attendance, from the first submission to the coordinator’s review.',
            'Kehadiran disimpan, daripada penyerahan awal hingga semakan penyelaras.',
          ),
        ),
        if (family) ...[
          Surface(
            color: Palette.soft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  c.t('Shared with your family', 'Dikongsi dengan keluarga'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (c.session!.elders.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'attendance-elder-${c.session!.selectedElderId}',
                    ),
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
                const SizedBox(height: 12),
                Text(
                  c.t(
                    'Attendance history follows daily-sharing consent. Family booking is a separate permission. You cannot submit or review on the elder’s behalf.',
                    'Sejarah kehadiran mengikut kebenaran perkongsian harian. Tempahan keluarga ialah kebenaran berasingan. Anda tidak boleh menghantar atau menyemak bagi pihak warga emas.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (w.error != null)
          CommunityError(w.error!.message(c.malay), retry: w.retry)
        else if (family && c.session!.selectedElder?.sharing != true)
          PreviewEmpty(
            icon: Icons.lock_outline,
            title: c.t('Attendance is private.', 'Kehadiran adalah peribadi.'),
            description: c.session!.elders.isEmpty
                ? c.t(
                    'No elder is linked to your household.',
                    'Tiada warga emas terpaut dengan isi rumah anda.',
                  )
                : c.t(
                    'Your elder can enable daily sharing to let you see their attendance. Booking permission does not grant access.',
                    'Warga emas boleh mengaktifkan perkongsian harian untuk memaparkan kehadiran. Kebenaran tempahan tidak memberikan akses.',
                  ),
          )
        else if (w.loading)
          const LinearProgressIndicator()
        else if (w.records.isEmpty)
          PreviewEmpty(
            icon: Icons.event_available_outlined,
            title: c.t(
              'Your next good day starts here.',
              'Hari baik seterusnya bermula di sini.',
            ),
            description: c.t(
              'Submitted, verified and unverified attendance will appear here. Companion activity attendance is saved after both participants confirm.',
              'Kehadiran yang dihantar, disahkan dan tidak disahkan akan dipaparkan di sini. Kehadiran aktiviti bersama teman disimpan selepas kedua-dua peserta mengesahkan.',
            ),
          )
        else
          for (final r in w.records)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: AttendanceRecordCard(r),
            ),
        const SizedBox(height: 18),
        Text(
          c.t(
            'Verified participation is recorded. Coin awards and redemption are awaiting the agreed reward policy.',
            'Penyertaan yang disahkan direkodkan. Pemberian syiling dan penebusan menunggu dasar ganjaran yang dipersetujui.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class AttendanceRecordCard extends StatelessWidget {
  const AttendanceRecordCard(this.record, {super.key, this.compact = false});
  final ActivityAttendance record;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), r = record;
    final a = c.community?.activities
        .where((a) => a.id == r.activityId)
        .firstOrNull;
    final place = c.community?.places
        .where((p) => p.id == a?.placeId)
        .firstOrNull;
    return Surface(
      key: ValueKey('attendance-${r.id}'),
      padding: EdgeInsets.all(compact ? 18 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pill(
                attendanceLabel(r.status, c.malay),
                gold: r.status == AttendanceStatus.rejected,
                icon: r.status == AttendanceStatus.verified
                    ? Icons.verified_outlined
                    : Icons.schedule,
              ),
              if (r.sessionManaged)
                Pill(
                  c.t('With a companion', 'Bersama teman'),
                  icon: Icons.people_outline,
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (!compact)
            Text(
              a?.title.inLanguage(c.malay) ??
                  c.t(
                    'Activity reference: ${r.activityId}',
                    'Rujukan aktiviti: ${r.activityId}',
                  ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          if (!compact && a != null) ...[
            const SizedBox(height: 8),
            Text(
              sessionWhen(a.startsAt, a.endsAt, c.malay),
              style: const TextStyle(color: Palette.muted),
            ),
          ],
          if (!compact && place != null) ...[
            const SizedBox(height: 8),
            Text(place.name),
          ],
          if (c.role == AppRole.coordinator) ...[
            const SizedBox(height: 12),
            Text(
              c.t(
                'Elder reference: ${r.elderId}',
                'Rujukan warga emas: ${r.elderId}',
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(switch (r.status) {
            AttendanceStatus.submitted =>
              c.role == AppRole.coordinator
                  ? c.t('Waiting for your review.', 'Menunggu semakan anda.')
                  : c.t(
                      'Your coordinator will check attendance before verifying it.',
                      'Penyelaras akan menyemak kehadiran sebelum mengesahkannya.',
                    ),
            AttendanceStatus.verified =>
              r.sessionManaged
                  ? c.t(
                      'Recorded through both companion-session confirmations.',
                      'Direkodkan melalui pengesahan kedua-dua peserta sesi teman.',
                    )
                  : c.t(
                      'Attendance checked by your coordinator.',
                      'Kehadiran disemak oleh penyelaras anda.',
                    ),
            AttendanceStatus.rejected => c.t(
              'The coordinator could not verify this attendance. The review is final for this activity.',
              'Penyelaras tidak dapat mengesahkan kehadiran ini. Semakan adalah muktamad untuk aktiviti ini.',
            ),
          }),
          if (r.reviewNote != null) ...[
            const Divider(),
            Text(
              c.t('Coordinator’s note', 'Nota penyelaras'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(r.reviewNote!),
          ],
          if (r.verificationMethod != null && !r.sessionManaged) ...[
            const SizedBox(height: 10),
            Text(
              r.verificationMethod == 'organizer_roster'
                  ? c.t(
                      'Checked against the organizer’s roster',
                      'Disemak dengan senarai kehadiran penganjur',
                    )
                  : c.t(
                      'Observed by the coordinator',
                      'Diperhatikan oleh penyelaras',
                    ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          Text(
            '${c.t("Saved", "Disimpan")} · ${activityDate(r.updatedAt, c.malay)} · ${malaysiaTime(r.updatedAt)} MYT',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (c.role == AppRole.coordinator && r.reviewable) ...[
            const SizedBox(height: 18),
            EmasButton(
              key: ValueKey('review-attendance-${r.id}'),
              label: c.t('Review attendance', 'Semak kehadiran'),
              onPressed:
                  a == null ||
                      a.participationMode != 'in_person' ||
                      a.endsAt.isAfter(c.community!.now) ||
                      c.attendance!.actions.containsKey('review:${r.id}')
                  ? null
                  : () => showEmasSheet(
                      context,
                      AttendanceSheetGuard(
                        token: c.attendance!.viewToken,
                        child: _ReviewAttendance(r.id),
                      ),
                    ),
            ),
            if (a == null || a.endsAt.isAfter(c.community!.now))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  c.t(
                    'Review is available when the recorded in-person activity has ended.',
                    'Semakan tersedia selepas aktiviti bersemuka yang direkodkan tamat.',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class AttendanceReviewQueue extends StatelessWidget {
  const AttendanceReviewQueue({super.key});
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.attendance!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommunityHeading(
          c.t(
            'Every good day, accounted for.',
            'Setiap hari baik, direkodkan.',
          ),
          c.t(
            'Check submitted attendance in your township using your observation or a trusted organizer roster.',
            'Semak kehadiran yang dihantar dalam perbandaran anda menggunakan pemerhatian atau senarai kehadiran penganjur yang dipercayai.',
          ),
        ),
        for (final name in w.actions.keys.toList()) ...[
          Text(
            c.t(
              'Attendance action awaiting a response',
              'Tindakan kehadiran menunggu jawapan',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          PendingAttendanceAction(name),
          const SizedBox(height: 18),
        ],
        if (w.error != null)
          CommunityError(w.error!.message(c.malay), retry: w.retry)
        else if (w.loading || c.community?.catalogLoading == true)
          const LinearProgressIndicator()
        else if (c.community?.catalogError != null)
          CommunityError(
            c.community!.catalogError!.message(c.malay),
            retry: c.community!.retry,
          )
        else if (w.records.isEmpty)
          PreviewEmpty(
            icon: Icons.task_alt,
            title: c.t('All caught up.', 'Semua telah disemak.'),
            description: c.t(
              'No attendance is waiting for review. New elder submissions appear here automatically.',
              'Tiada kehadiran menunggu semakan. Penyerahan baharu warga emas muncul di sini secara automatik.',
            ),
          )
        else
          for (final r in w.records)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: AttendanceRecordCard(r),
            ),
      ],
    );
  }
}

class _ReviewAttendance extends StatefulWidget {
  const _ReviewAttendance(this.id);
  final String id;
  @override
  State<_ReviewAttendance> createState() => _ReviewAttendanceState();
}

class _ReviewAttendanceState extends State<_ReviewAttendance> {
  final _form = GlobalKey<FormState>(), _note = TextEditingController();
  String _decision = 'verify';
  String? _method;
  void _done() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    sessionToast(
      context,
      'Attendance review saved.',
      'Semakan kehadiran disimpan.',
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.attendance!;
    final name = 'review:${widget.id}',
        r = w.record(widget.id),
        pending = w.actions.containsKey('review:${widget.id}');
    if (r == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            c.t(
              'This attendance has left the review queue.',
              'Kehadiran ini telah meninggalkan senarai semakan.',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Text(
            c.t(
              'It may already have been reviewed. Close this sheet to see the latest queue.',
              'Ia mungkin telah disemak. Tutup paparan ini untuk melihat senarai terkini.',
            ),
          ),
          PendingAttendanceAction(name, onSuccess: _done),
        ],
      );
    }
    final a = c.community?.activities
        .where((a) => a.id == r.activityId)
        .firstOrNull;
    final eligible =
        a != null &&
        a.participationMode == 'in_person' &&
        !a.endsAt.isAfter(c.community!.now) &&
        r.reviewable;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            c.t(
              'A careful check, a trusted record.',
              'Semakan teliti, rekod dipercayai.',
            ),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            a?.title.inLanguage(c.malay) ?? r.activityId,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            c.t(
              'Elder reference: ${r.elderId}',
              'Rujukan warga emas: ${r.elderId}',
            ),
          ),
          if (a != null) ...[
            const SizedBox(height: 8),
            Text(sessionWhen(a.startsAt, a.endsAt, c.malay)),
          ],
          const Divider(),
          Text(
            c.t(
              'Verify only if you personally observed attendance or checked a trusted organizer roster. This records your review; it does not fetch or check a roster for you.',
              'Sahkan hanya jika anda sendiri melihat kehadiran atau menyemak senarai kehadiran penganjur yang dipercayai. Ini merekodkan semakan anda; ia tidak mendapatkan atau menyemak senarai bagi pihak anda.',
            ),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            key: const ValueKey('attendance-review-decision'),
            initialValue: _decision,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: c.t('Decision', 'Keputusan'),
            ),
            items: [
              DropdownMenuItem(
                value: 'verify',
                child: Text(c.t('Verify attendance', 'Sahkan kehadiran')),
              ),
              DropdownMenuItem(
                value: 'reject',
                child: Text(c.t('Cannot verify', 'Tidak dapat mengesahkan')),
              ),
            ],
            onChanged: pending ? null : (v) => setState(() => _decision = v!),
          ),
          if (_decision == 'verify') ...[
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              key: const ValueKey('attendance-review-method'),
              initialValue: _method,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: c.t(
                  'How did you check?',
                  'Bagaimana anda menyemak?',
                ),
              ),
              items: [
                DropdownMenuItem(
                  value: 'coordinator_observed',
                  child: Text(
                    c.t('I observed attendance', 'Saya melihat kehadiran'),
                  ),
                ),
                DropdownMenuItem(
                  value: 'organizer_roster',
                  child: Text(
                    c.t(
                      'I checked the organizer roster',
                      'Saya menyemak senarai penganjur',
                    ),
                  ),
                ),
              ],
              onChanged: pending ? null : (v) => setState(() => _method = v),
              validator: (v) => _decision == 'verify' && v == null
                  ? c.t(
                      'Choose how you checked attendance.',
                      'Pilih cara anda menyemak kehadiran.',
                    )
                  : null,
            ),
          ],
          const SizedBox(height: 18),
          TextFormField(
            key: const ValueKey('attendance-review-note'),
            controller: _note,
            enabled: !pending,
            minLines: 3,
            maxLines: 6,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: _decision == 'verify'
                  ? c.t('Factual review note', 'Nota semakan berdasarkan fakta')
                  : c.t(
                      'Reason attendance could not be verified',
                      'Sebab kehadiran tidak dapat disahkan',
                    ),
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty || (v ?? '').trim().length > 500
                ? c.t(
                    'Enter a note of 1–500 characters.',
                    'Masukkan nota 1–500 aksara.',
                  )
                : null,
          ),
          const SizedBox(height: 14),
          Text(
            c.t(
              'This review is final for this activity. Verification records participation; coin awards are still pending policy.',
              'Semakan ini muktamad untuk aktiviti ini. Pengesahan merekodkan penyertaan; pemberian syiling masih menunggu dasar.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          EmasButton(
            key: const ValueKey('save-attendance-review'),
            label: c.t('Save review', 'Simpan semakan'),
            onPressed: pending || !eligible
                ? null
                : () async {
                    if (!_form.currentState!.validate()) return;
                    final saved = await w.review(r.id, {
                      'decision': _decision,
                      'verificationMethod': _decision == 'verify'
                          ? _method
                          : null,
                      'note': _note.text.trim(),
                    });
                    if (saved) _done();
                  },
          ),
          PendingAttendanceAction(name, onSuccess: _done),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }
}

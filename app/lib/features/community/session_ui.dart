import 'package:flutter/material.dart';
import '../../app/preview_controller.dart';
import '../../models/session_models.dart';
import '../../models/backend_models.dart';
import '../../models/community_models.dart';
import '../../shared/design_system.dart';

String requestStateLabel(RequestState state, bool bm) => switch (state) {
  RequestState.requested => bm ? 'Menunggu penyelaras' : 'Awaiting coordinator',
  RequestState.assigned => bm ? 'Menunggu pembantu' : 'Awaiting helper',
  RequestState.accepted => bm ? 'Sedia untuk sesi' : 'Ready for the session',
  RequestState.inProgress =>
    bm ? 'Sesi sedang berjalan' : 'Session in progress',
  RequestState.awaitingConfirmation =>
    bm ? 'Menunggu dua pengesahan' : 'Awaiting both confirmations',
  RequestState.completed =>
    bm ? 'Disahkan oleh kedua-duanya' : 'Confirmed by both',
  RequestState.cancelled => bm ? 'Dibatalkan' : 'Cancelled',
};
String sessionTask(String task, bool bm) => switch (task) {
  'walk_with_me' => bm ? 'Teman berjalan' : 'Walk with me',
  'sit_with_me' => bm ? 'Teman duduk' : 'Sit with me',
  'carry_light_item' => bm ? 'Bawa barang ringan' : 'Carry a light item',
  'phone_help' => bm ? 'Bantuan telefon' : 'Phone help',
  _ => bm ? 'Bantuan teman' : 'Companion help',
};
String genderLabel(String value, bool bm) => switch (value) {
  'female' => bm ? 'Wanita' : 'Female',
  'male' => bm ? 'Lelaki' : 'Male',
  _ => bm ? 'Tiada pilihan' : 'No preference',
};
String sessionWhen(DateTime start, DateTime end, bool bm) =>
    '${activityDate(start, bm)} · ${malaysiaTime(start)}–${malaysiaDate(start) == malaysiaDate(end) ? "" : "${activityDate(end, bm)} · "}${malaysiaTime(end)} MYT';
void sessionToast(BuildContext context, String en, String bm) {
  final c = PreviewScope.of(context);
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(c.t(en, bm))));
}

class PendingSessionAction extends StatelessWidget {
  const PendingSessionAction(this.name, {super.key, this.onSuccess});
  final String name;
  final VoidCallback? onSuccess;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.sessions!;
    final action = w.actions[name];
    if (action == null) return const SizedBox.shrink();
    if (action.busy) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                c.t('Saving your action…', 'Menyimpan tindakan anda…'),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Surface(
        color: Palette.sand,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                action.error?.message(c.malay) ??
                    c.t(
                      'This action is ready to retry.',
                      'Tindakan ini boleh dicuba semula.',
                    ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              c.t(
                'Retrying keeps the same request and details.',
                'Cuba semula mengekalkan permintaan dan butiran yang sama.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            EmasButton(
              label: c.t('Try again', 'Cuba lagi'),
              secondary: true,
              onPressed: () async {
                final saved = await w.retryAction(name);
                // The action's card can leave a filtered queue before the RPC
                // resolves. Its owning sheet decides whether it is still active.
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

import 'package:flutter/material.dart';
import '../../app/preview_controller.dart';
import '../../models/companion_ui_models.dart';
import '../../models/preview_models.dart';
import '../../shared/design_system.dart';

String taskName(CompanionTask task, bool bm) => switch (task) {
  CompanionTask.walkWithMe => bm ? 'Teman berjalan' : 'Walk with me',
  CompanionTask.sitWithMe => bm ? 'Teman duduk' : 'Sit with me',
  CompanionTask.phoneHelp => bm ? 'Bantuan telefon' : 'Phone help',
  CompanionTask.carryLightItem =>
    bm ? 'Bawa barang ringan' : 'Carry a light item',
};
String stageName(DemoSessionStage stage, bool bm) => switch (stage) {
  DemoSessionStage.requested =>
    bm ? 'Menunggu penyelaras' : 'Awaiting coordinator',
  DemoSessionStage.assigned => bm ? 'Menunggu pembantu' : 'Awaiting helper',
  DemoSessionStage.accepted =>
    bm ? 'Sedia untuk sesi' : 'Ready for the session',
  DemoSessionStage.inProgress =>
    bm ? 'Sesi sedang berjalan' : 'Session in progress',
  DemoSessionStage.awaitingConfirmation =>
    bm ? 'Menunggu dua pengesahan' : 'Awaiting both confirmations',
  DemoSessionStage.completed =>
    bm ? 'Disahkan oleh kedua-duanya' : 'Confirmed by both',
  DemoSessionStage.cancelled => bm ? 'Dibatalkan' : 'Cancelled',
};
String scopeToken(PreviewController c) => c.session?.connected == true
    ? '${c.session!.profile!.uid}/${c.session!.profile!.role}/${c.session!.profile!.townshipId}/${c.session!.profile!.householdId}/${c.role == AppRole.family ? c.session!.selectedElderId : "self"}'
    : 'preview/${c.role.name}';

/// Clears an open detail/form before an old account's content can remain visible.
class CommunitySheetGuard extends StatelessWidget {
  const CommunitySheetGuard({
    super.key,
    required this.token,
    required this.child,
  });
  final String token;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    if (token == scopeToken(c)) return child;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    });
    return const SizedBox.shrink();
  }
}

class CommunityHeading extends StatelessWidget {
  const CommunityHeading(
    this.title,
    this.description, {
    super.key,
    this.eyebrow,
  });
  final String title, description;
  final String? eyebrow;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 26),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Text(
            eyebrow!,
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w600,
              color: Palette.muted,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          title,
          style: TextStyle(
            fontSize: MediaQuery.sizeOf(context).width < 600 ? 30 : 36,
            height: 1.2,
            letterSpacing: -1.1,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Text(description, style: const TextStyle(color: Palette.muted)),
      ],
    ),
  );
}

class SampleJourneyBanner extends StatelessWidget {
  const SampleJourneyBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Surface(
        padding: const EdgeInsets.all(18),
        color: Palette.sand,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.science_outlined, color: Palette.gold, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.t(
                      'Sample journey · stays in this tab',
                      'Perjalanan contoh · kekal dalam tab ini',
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Palette.gold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.t(
                      'No booking is sent. Switch preview roles to try each person’s part. Reloading clears these sample requests.',
                      'Tiada tempahan dihantar. Tukar peranan pratonton untuk mencuba setiap peranan. Muat semula untuk mengosongkan permintaan contoh.',
                    ),
                    style: const TextStyle(fontSize: 12, color: Palette.gold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> openSampleJourney(BuildContext context) async {
  final c = PreviewScope.of(context);
  await c.enterPhase2Preview();
}

class BookingConnectionNote extends StatelessWidget {
  const BookingConnectionNote({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    return Surface(
      padding: EdgeInsets.all(compact ? 18 : 24),
      color: Palette.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconTile(Icons.person_add_alt_1_outlined),
          const SizedBox(height: 16),
          Text(
            c.t(
              'A companion, when you need one.',
              'Teman, apabila diperlukan.',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            c.t(
              'Booking and session actions are not connected yet. You can review the request form or explore the sample journey.',
              'Tempahan dan tindakan sesi belum disambungkan. Anda boleh menyemak borang permintaan atau meneroka perjalanan contoh.',
            ),
          ),
          const SizedBox(height: 16),
          EmasButton(
            label: c.t(
              'Open sample journey · signs out',
              'Buka perjalanan contoh · log keluar',
            ),
            secondary: true,
            onPressed: () => openSampleJourney(context),
          ),
        ],
      ),
    );
  }
}

class CommunityError extends StatelessWidget {
  const CommunityError(this.message, {super.key, this.retry});
  final String message;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconTile(Icons.info_outline),
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: Text(message)),
          if (retry != null) ...[
            const SizedBox(height: 14),
            EmasButton(
              label: c.t('Try again', 'Cuba lagi'),
              secondary: true,
              onPressed: retry,
            ),
          ],
        ],
      ),
    );
  }
}

void runSampleAction(BuildContext context, VoidCallback action) {
  try {
    action();
  } on StateError {
    final c = PreviewScope.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          c.t(
            'This sample action is no longer available. Check the current role and session status.',
            'Tindakan contoh ini tidak lagi tersedia. Semak peranan dan status sesi semasa.',
          ),
        ),
      ),
    );
  }
}

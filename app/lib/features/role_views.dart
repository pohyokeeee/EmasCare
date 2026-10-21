import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../app/app_shell.dart';
import '../app/preview_controller.dart';
import '../models/preview_models.dart';
import '../shared/design_system.dart';
import '../shared/park_art.dart';
import 'connected/connected_home.dart';
import 'community/activity_catalog.dart';
import 'community/companion_workspace.dart';
import '../data/phase2_samples.dart';

class RoleContent extends StatelessWidget {
  const RoleContent({super.key});
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    if (c.session?.connected == true) return const ConnectedHome();
    if (c.role == AppRole.coordinator &&
        c.destination == Destination.activities) {
      return const CompanionWorkspace();
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
    if (c.role == AppRole.helper &&
        c.destination == Destination.today &&
        c.demo.requests.any((r) => r.helperName != null)) {
      return const CompanionWorkspace();
    }
    if (c.role == AppRole.coordinator) return const _Coordinator();
    return switch (c.destination) {
      Destination.today => switch (c.role) {
        AppRole.elder => const _ElderHome(),
        AppRole.family => const _FamilyHome(),
        _ => const _HelperHome(),
      },
      Destination.activities => const CommunityActivities(),
      Destination.companion => const CompanionWorkspace(),
      Destination.rewards =>
        c.role == AppRole.family ? const _Community() : const _Wallet(),
    };
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title, this.subtitle, {this.eyebrow});
  final String title, subtitle;
  final String? eyebrow;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Text(
            eyebrow!,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: Palette.muted,
            ),
          ),
          const SizedBox(height: 9),
        ],
        Text(
          title,
          style: TextStyle(
            fontSize: MediaQuery.sizeOf(context).width < 600 ? 29 : 37,
            height: 1.2,
            letterSpacing: -1.2,
            fontWeight: FontWeight.w600,
            color: Palette.ink,
          ),
        ),
        const SizedBox(height: 10),
        Text(subtitle, style: const TextStyle(color: Palette.muted)),
      ],
    ),
  );
}

class _Columns extends StatelessWidget {
  const _Columns({required this.main, required this.aside});
  final Widget main, aside;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) =>
        box.maxWidth >= 900 && MediaQuery.textScalerOf(context).scale(1) < 1.2
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: main),
              const SizedBox(width: 26),
              SizedBox(width: 280, child: aside),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [main, const SizedBox(height: 26), aside],
          ),
  );
}

class _ElderHome extends StatelessWidget {
  const _ElderHome();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          c.t('Good morning, Mr Tan ☀', 'Selamat pagi, Mr Tan ☀'),
          c.t(
            'A good day to get out, or simply say hello.',
            'Hari yang indah untuk keluar atau bertanya khabar.',
          ),
          eyebrow: c.t(
            'WEDNESDAY, 21 OCTOBER · SAMPLE DAY',
            'RABU, 21 OKTOBER · HARI CONTOH',
          ),
        ),
        _Columns(
          main: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CheckInHero(),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, box) {
                  final narrow =
                      box.maxWidth < 500 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.1;
                  final actions = [
                    _ActionCard(
                      icon: CupertinoIcons.sun_max,
                      title: c.t('Let’s go out', 'Jom keluar'),
                      description: c.t(
                        'Something lovely nearby',
                        'Aktiviti menarik berdekatan',
                      ),
                      onTap: () =>
                          c.navigate(destination: Destination.activities),
                    ),
                    _ActionCard(
                      icon: CupertinoIcons.person_2,
                      title: c.t('Find a little company', 'Minta teman'),
                      description: c.t(
                        'Your neighbour, by your side',
                        'Jiran sedia menemani',
                      ),
                      onTap: () =>
                          c.navigate(destination: Destination.companion),
                    ),
                  ];
                  return narrow
                      ? Column(
                          children: [
                            actions[0],
                            const SizedBox(height: 12),
                            actions[1],
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: actions[0]),
                            const SizedBox(width: 16),
                            Expanded(child: actions[1]),
                          ],
                        );
                },
              ),
              const SizedBox(height: 30),
              TitleRow(
                c.t('Around the neighbourhood', 'Sekitar kejiranan'),
                action: c.t('View all →', 'Lihat semua →'),
                onAction: () => c.navigate(destination: Destination.activities),
              ),
              ActivityGrid(
                activities: c.repository.activities.take(2).toList(),
              ),
              const SizedBox(height: 20),
              const _VoiceInvitation(),
            ],
          ),
          aside: Column(
            children: [
              const _NextOuting(),
              const SizedBox(height: 20),
              const _WeekProgress(),
              const SizedBox(height: 20),
              const _Neighbours(),
            ],
          ),
        ),
      ],
    );
  }
}

class _CheckInHero extends StatelessWidget {
  const _CheckInHero();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    final ok = c.repository.checkedIn;
    return LayoutBuilder(
      builder: (context, box) {
        final art =
            box.maxWidth > 580 &&
            MediaQuery.textScalerOf(context).scale(1) < 1.2;
        return SizedBox(
          width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: ColoredBox(
              color: Palette.green,
              child: Stack(
                children: [
                  if (art)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      top: 0,
                      width: box.maxWidth * .50,
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Colors.transparent, Colors.white],
                          stops: [0, .28],
                        ).createShader(bounds),
                        blendMode: BlendMode.dstIn,
                        child: const ParkArt(dark: true),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(28),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: art ? box.maxWidth * .58 : double.infinity,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                CupertinoIcons.heart,
                                size: 16,
                                color: Color(0xFFD5E3D2),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  c.t(
                                    'SAYA OK · DAILY CHECK-IN',
                                    'SAYA OK · DAFTAR MASUK HARIAN',
                                  ),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 1.2,
                                    color: Color(0xFFD5E3D2),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 21),
                          Text(
                            ok
                                ? c.t(
                                    'Lovely to hear\nfrom you.',
                                    'Gembira mendengar\nkhabar anda.',
                                  )
                                : c.t(
                                    'A little hello.\nA brighter day.',
                                    'Sedikit sapaan.\nHari lebih ceria.',
                                  ),
                            style: const TextStyle(
                              fontSize: 34,
                              height: 1.17,
                              letterSpacing: -1,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            ok
                                ? c.t(
                                    'Your sample check-in is saved for this preview.',
                                    'Daftar masuk contoh disimpan dalam pratonton ini.',
                                  )
                                : c.t(
                                    'How are you feeling today?',
                                    'Apa khabar anda hari ini?',
                                  ),
                            style: const TextStyle(
                              color: Color(0xFFDCE8DA),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 23),
                          EmasButton(
                            key: const ValueKey('preview-check-in'),
                            label: ok
                                ? c.t(
                                    'Checked in · Preview',
                                    'Sudah daftar · Pratonton',
                                  )
                                : c.t('Saya OK — I’m okay', 'Saya OK'),
                            icon: ok
                                ? CupertinoIcons.check_mark
                                : CupertinoIcons.heart_fill,
                            white: true,
                            onPressed: ok
                                ? null
                                : () {
                                    c.repository.previewCheckIn();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          c.t(
                                            'Sample check-in updated. No message was sent.',
                                            'Daftar masuk contoh dikemas kini. Tiada mesej dihantar.',
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });
  final IconData icon;
  final String title, description;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(19),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Padding(
        padding: const EdgeInsets.all(19),
        child: Row(
          children: [
            IconTile(icon),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 11, color: Palette.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              CupertinoIcons.chevron_right,
              size: 13,
              color: Palette.muted,
            ),
          ],
        ),
      ),
    ),
  );
}

class _NextOuting extends StatelessWidget {
  const _NextOuting();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.t('Your next little adventure', 'Aktiviti anda seterusnya'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 49,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Palette.sand,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      c.t('THU', 'KHA'),
                      style: const TextStyle(fontSize: 10, color: Palette.gold),
                    ),
                    const Text(
                      '22',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                        color: Palette.gold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.t('Morning tai chi', 'Tai chi pagi'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      '10:00–11:00',
                      style: TextStyle(fontSize: 12, color: Palette.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          const Divider(height: 1),
          const SizedBox(height: 17),
          Row(
            children: [
              const Avatar('KL', size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c.t(
                    'With Kak Lina\nYour regular companion',
                    'Bersama Kak Lina\nTeman tetap anda',
                  ),
                  style: const TextStyle(fontSize: 12, height: 1.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Pill(
            c.t('Sample plan · not booked', 'Pelan contoh · belum ditempah'),
            icon: CupertinoIcons.calendar,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: EmasButton(
              label: c.t('See the plan', 'Lihat pelan'),
              secondary: true,
              onPressed: () =>
                  showActivity(context, c.repository.activities.first),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekProgress extends StatelessWidget {
  const _WeekProgress();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.t('One step at a time', 'Selangkah demi selangkah'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: CustomPaint(
                  painter: _Ring(.5),
                  child: const Center(
                    child: Text(
                      '1 / 2',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 19,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  c.t(
                    'Outings this week\nA little fresh air goes far.',
                    'Aktiviti minggu ini\nUdara segar menyegarkan.',
                  ),
                  style: const TextStyle(fontSize: 12, height: 1.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            c.t(
              'Illustrative progress · confirmed outings later',
              'Kemajuan contoh · aktiviti disahkan akan datang',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Ring extends CustomPainter {
  _Ring(this.value);
  final double value;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = Palette.soft;
    canvas.drawOval(r.deflate(5), p);
    p.color = Palette.green;
    canvas.drawArc(r.deflate(5), -math.pi / 2, math.pi * 2 * value, false, p);
  }

  @override
  bool shouldRepaint(_Ring old) => old.value != value;
}

class _Neighbours extends StatelessWidget {
  const _Neighbours();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    return Surface(
      color: const Color(0xFFF0F1E8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Avatar('KL', size: 34),
              Avatar('PR', size: 34),
              Avatar('AL', size: 34),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            c.t(
              'Familiar faces.\nA place to belong.',
              'Wajah yang dikenali.\nKomuniti untuk anda.',
            ),
            style: const TextStyle(
              fontSize: 17,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            c.t('Good company, close to home.', 'Teman mesra, dekat di rumah.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class ActivityGrid extends StatelessWidget {
  const ActivityGrid({super.key, required this.activities});
  final List<CommunityActivity> activities;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final n = MediaQuery.textScalerOf(context).scale(1) > 1.1
          ? 1
          : box.maxWidth > 1040
          ? 3
          : box.maxWidth >= 520
          ? 2
          : 1;
      final width = (box.maxWidth - (n - 1) * 18) / n;
      return Wrap(
        spacing: 18,
        runSpacing: 18,
        children: [
          for (final a in activities)
            SizedBox(width: width, child: _ActivityCard(a)),
        ],
      );
    },
  );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard(this.activity);
  final CommunityActivity activity;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    final a = activity;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('activity-${a.id}'),
        onTap: () => showActivity(context, a),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 137,
              width: double.infinity,
              child: ParkArt(garden: a.garden),
            ),
            Padding(
              padding: const EdgeInsets.all(19),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${a.day.inLanguage(c.malay)} · ${a.time}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Palette.gold,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    a.title.inLanguage(c.malay),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.4,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    a.place,
                    style: const TextStyle(fontSize: 12, color: Palette.muted),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Pill(
                        c.t('Step-free', 'Tanpa tangga'),
                        icon: CupertinoIcons.check_mark_circled,
                      ),
                      Pill(
                        c.t(
                          '${a.walkMinutes} min walk',
                          '${a.walkMinutes} min jalan',
                        ),
                        icon: CupertinoIcons.location,
                      ),
                    ],
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

void showActivity(BuildContext context, CommunityActivity a) {
  final c = PreviewScope.of(context);
  final activity = sampleActivities(
    c.demo.seededAt,
  ).where((item) => item.id == a.id).firstOrNull;
  if (activity != null) openActivity(context, activity);
}

class _VoiceInvitation extends StatelessWidget {
  const _VoiceInvitation();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    return _ActionCard(
      icon: CupertinoIcons.waveform,
      title: c.t('Prefer to say it?', 'Lebih suka bercakap?'),
      description: c.t(
        'Teman voice · try your device',
        'Suara Teman · cuba peranti anda',
      ),
      onTap: () => showSettings(context),
    );
  }
}

class _FamilyHome extends StatelessWidget {
  const _FamilyHome();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    final ok = c.repository.checkedIn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          c.t('Close, even from afar.', 'Sentiasa dekat walau berjauhan.'),
          c.t(
            'A little peace of mind for the people you love.',
            'Sedikit ketenangan untuk insan tersayang.',
          ),
          eyebrow: c.t('DANIEL’S FAMILY SPACE', 'RUANG KELUARGA DANIEL'),
        ),
        _Columns(
          main: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _PersonRow('MT', 'Mr Tan', 'City of Elmina'),
                    const SizedBox(height: 24),
                    Pill(
                      ok
                          ? c.t(
                              'Checked in · local preview',
                              'Sudah daftar · pratonton setempat',
                            )
                          : c.t(
                              'Awaiting sample check-in',
                              'Menunggu daftar masuk contoh',
                            ),
                      icon: ok
                          ? CupertinoIcons.check_mark_circled
                          : CupertinoIcons.clock,
                    ),
                    const SizedBox(height: 17),
                    Text(
                      ok
                          ? c.t('A hello from Dad.', 'Sapaan daripada ayah.')
                          : c.t(
                              'His day, at his own pace.',
                              'Harinya, mengikut rentaknya.',
                            ),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      c.t(
                        'Try the Saya OK button in the Elder preview, then return here to see the local status update.',
                        'Cuba butang Saya OK dalam pratonton Warga emas, kemudian kembali untuk melihat status setempat.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              TitleRow(
                c.t('Something to look forward to', 'Aktiviti yang dinanti'),
              ),
              ActivityGrid(
                activities: c.repository.activities.take(2).toList(),
              ),
            ],
          ),
          aside: Column(
            children: [
              const _WeekProgress(),
              const SizedBox(height: 20),
              PreviewEmpty(
                icon: CupertinoIcons.lock_shield,
                title: c.t('Shared by choice', 'Berkongsi dengan rela'),
                description: c.t(
                  'Sample sharing is enabled. Real sharing and booking need the elder’s separate consent and backend permission checks.',
                  'Perkongsian contoh diaktifkan. Perkongsian dan tempahan sebenar memerlukan persetujuan berasingan warga emas dan semakan kebenaran pelayan.',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HelperHome extends StatelessWidget {
  const _HelperHome();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          c.t(
            'A little of your time.\nA lot of difference.',
            'Sedikit masa anda.\nBesar maknanya.',
          ),
          c.t(
            'Thank you for being a familiar face, Kak Lina.',
            'Terima kasih kerana sedia menemani, Kak Lina.',
          ),
          eyebrow: c.t('YOUR HELPER SPACE', 'RUANG PEMBANTU ANDA'),
        ),
        _Columns(
          main: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Surface(
                child: Row(
                  children: [
                    const IconTile(CupertinoIcons.calendar_badge_plus),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.t('Available to help', 'Sedia membantu'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            c.t(
                              'Local preview · not sent to coordinator',
                              'Pratonton setempat · tidak dihantar ke penyelaras',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Semantics(
                      label: c.t('Available to help', 'Sedia membantu'),
                      child: CupertinoSwitch(
                        key: const ValueKey('helper-availability'),
                        value: c.repository.helperAvailable,
                        onChanged: c.repository.previewSetAvailability,
                        activeTrackColor: Palette.green,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TitleRow(c.t('Your next session', 'Sesi anda seterusnya')),
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _PersonRow('MT', 'Mr Tan', 'Central Park · Gate B'),
                    const SizedBox(height: 18),
                    Text(
                      c.t('Morning tai chi', 'Tai chi pagi'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 7),
                    Text(c.t('Tomorrow · 10:00–11:00', 'Esok · 10:00–11:00')),
                    const SizedBox(height: 16),
                    Pill(
                      c.t(
                        'Assigned · sample session',
                        'Ditugaskan · sesi contoh',
                      ),
                    ),
                    const SizedBox(height: 20),
                    EmasButton(
                      label: c.t('See your companion', 'Lihat teman anda'),
                      onPressed: () =>
                          c.navigate(destination: Destination.companion),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const _VoiceInvitation(),
            ],
          ),
          aside: Column(
            children: [
              _Metric(
                '4',
                c.t('moments of company', 'detik bersama'),
                c.t(
                  'Illustrative completed helping sessions',
                  'Sesi bantuan selesai contoh',
                ),
              ),
              const SizedBox(height: 20),
              const _Neighbours(),
            ],
          ),
        ),
      ],
    );
  }
}

class _Wallet extends StatelessWidget {
  const _Wallet();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          c.t(
            'Little moments, appreciated.',
            'Detik kecil, besar penghargaan.',
          ),
          c.t(
            'A thank-you for taking part and showing up for each other.',
            'Tanda penghargaan kerana menyertai dan saling membantu.',
          ),
        ),
        _Columns(
          main: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Surface(
                color: Palette.green,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.t('YOUR COINS', 'SYILING ANDA'),
                      style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.5,
                        color: Color(0xFFDCE8DA),
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      '—',
                      style: TextStyle(fontSize: 54, color: Colors.white),
                    ),
                    Text(
                      c.t('Wallet not connected', 'Dompet belum disambung'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      c.t(
                        'Elders and helpers earn coins after eligible verified completions. Coin rates are still being agreed.',
                        'Warga emas dan pembantu menerima syiling selepas penyertaan layak disahkan selesai. Kadar syiling masih dalam perbincangan.',
                      ),
                      style: const TextStyle(color: Color(0xFFDCE8DA)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 27),
              TitleRow(
                c.t(
                  'A little something in return',
                  'Sedikit ganjaran untuk anda',
                ),
              ),
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const IconTile(CupertinoIcons.gift, gold: true),
                    const SizedBox(height: 18),
                    Text(
                      c.t('Elmina demo voucher', 'Baucar demo Elmina'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Pill(
                      c.t(
                        '100 coins · sample voucher',
                        '100 syiling · baucar contoh',
                      ),
                      gold: true,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      c.t(
                        'A preview of redemption. No voucher is issued and no coins are deducted.',
                        'Pratonton penebusan. Tiada baucar dikeluarkan dan tiada syiling ditolak.',
                      ),
                    ),
                    const SizedBox(height: 20),
                    EmasButton(
                      label: c.t(
                        'Redemption not connected',
                        'Penebusan belum disambung',
                      ),
                      icon: CupertinoIcons.lock,
                      onPressed: null,
                    ),
                  ],
                ),
              ),
            ],
          ),
          aside: PreviewEmpty(
            icon: CupertinoIcons.ticket,
            title: c.t('My vouchers', 'Baucar saya'),
            description: c.t(
              'Issued vouchers and your coin history will appear here once the backend is connected.',
              'Baucar dan sejarah syiling akan dipaparkan selepas pelayan disambung.',
            ),
          ),
        ),
      ],
    );
  }
}

class _Community extends StatelessWidget {
  const _Community();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          c.t(
            'A neighbourhood that shows up.',
            'Kejiranan yang saling membantu.',
          ),
          c.t(
            'A shared goal, one small outing at a time.',
            'Matlamat bersama, satu aktiviti pada satu masa.',
          ),
        ),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.t('100 outings, together', '100 aktiviti bersama'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              const LinearProgressIndicator(
                value: .8,
                color: Palette.green,
                backgroundColor: Palette.soft,
                borderRadius: BorderRadius.all(Radius.circular(10)),
                minHeight: 10,
              ),
              const SizedBox(height: 14),
              Text(
                c.t(
                  '80 / 100 · illustrative community progress',
                  '80 / 100 · kemajuan komuniti contoh',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                c.t(
                  'Confirmed activity counts and consented family cheers will connect later. There are no rankings or streak penalties.',
                  'Kiraan aktiviti disahkan dan sorakan keluarga dengan persetujuan akan disambung kemudian. Tiada kedudukan atau penalti.',
                ),
                style: const TextStyle(color: Palette.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const _Neighbours(),
      ],
    );
  }
}

class _Coordinator extends StatelessWidget {
  const _Coordinator();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    final d = c.destination;
    final title = switch (d) {
      Destination.today => c.t(
        'A clearer view of your community.',
        'Gambaran komuniti yang lebih jelas.',
      ),
      Destination.activities => c.t(
        'A little help, well coordinated.',
        'Bantuan yang tersusun.',
      ),
      Destination.companion => c.t(
        'Comfort starts with access.',
        'Keselesaan bermula dengan akses.',
      ),
      Destination.rewards => c.t(
        'The people behind the moments.',
        'Ahli di sebalik detik bersama.',
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          title,
          c.t(
            'Coordinator preview · City of Elmina · read-only sample data',
            'Pratonton penyelaras · City of Elmina · data contoh baca sahaja',
          ),
        ),
        if (d == Destination.today) ...[
          LayoutBuilder(
            builder: (context, box) {
              final n =
                  box.maxWidth < 650 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.1
                  ? 1
                  : 3;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final data in [
                    (
                      '${c.repository.checkedIn ? 9 : 8} / 12',
                      c.t('daily check-ins', 'daftar masuk harian'),
                    ),
                    (
                      '2',
                      c.t('requests to review', 'permintaan untuk disemak'),
                    ),
                    ('80', c.t('community outings', 'aktiviti komuniti')),
                  ])
                    SizedBox(
                      width: (box.maxWidth - (n - 1) * 16) / n,
                      child: _Metric(
                        data.$1,
                        data.$2,
                        c.t('Sample data', 'Data contoh'),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),
        ],
        if (d == Destination.today || d == Destination.activities) ...[
          TitleRow(
            c.t('Neighbour companion requests', 'Permintaan teman jiran'),
          ),
          Surface(
            child: Column(
              children: [
                for (var i = 0; i < c.repository.requests.length; i++) ...[
                  _RequestRow(c.repository.requests[i]),
                  if (i < c.repository.requests.length - 1) const Divider(),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          PreviewEmpty(
            icon: CupertinoIcons.slider_horizontal_3,
            title: c.t('Operations come next', 'Operasi akan datang'),
            description: c.t(
              'Assignment, missed-check-in follow-up, reports and availability summaries need the backend. Preview controls cannot contact or assign anyone.',
              'Penugasan, susulan daftar masuk, laporan dan ringkasan ketersediaan memerlukan pelayan. Pratonton tidak boleh menghubungi atau menugaskan sesiapa.',
            ),
          ),
        ],
        if (d == Destination.companion)
          ActivityGrid(activities: c.repository.activities),
        if (d == Destination.rewards)
          Surface(
            child: Column(
              children: [
                _PersonRow(
                  'MT',
                  'Mr Tan',
                  c.t('Elder · sample profile', 'Warga emas · profil contoh'),
                ),
                const Divider(),
                _PersonRow(
                  'KL',
                  'Kak Lina',
                  c.t('Helper · sample profile', 'Pembantu · profil contoh'),
                ),
                const Divider(),
                _PersonRow(
                  'DL',
                  'Daniel',
                  c.t('Family · sample profile', 'Keluarga · profil contoh'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.value, this.label, this.note);
  final String value, label, note;
  @override
  Widget build(BuildContext context) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 38,
            letterSpacing: -1.2,
            fontWeight: FontWeight.w600,
            color: Palette.green,
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Text(note, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _PersonRow extends StatelessWidget {
  const _PersonRow(this.initials, this.name, this.subtitle);
  final String initials, name, subtitle;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Avatar(initials, size: 49),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Palette.muted),
            ),
          ],
        ),
      ),
    ],
  );
}

class _RequestRow extends StatelessWidget {
  const _RequestRow(this.request);
  final RequestPreview request;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    final r = request;
    return LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(r.initials, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${r.activity} · ${r.time}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (box.maxWidth > 470) ...[
                const SizedBox(width: 12),
                Pill(
                  r.assigned
                      ? c.t('Assigned', 'Ditugaskan')
                      : c.t('Requested', 'Diminta'),
                  gold: !r.assigned,
                ),
              ],
            ],
          ),
          if (box.maxWidth <= 470)
            Padding(
              padding: const EdgeInsets.only(left: 50, top: 9),
              child: Pill(
                r.assigned
                    ? c.t('Assigned', 'Ditugaskan')
                    : c.t('Requested', 'Diminta'),
                gold: !r.assigned,
              ),
            ),
        ],
      ),
    );
  }
}

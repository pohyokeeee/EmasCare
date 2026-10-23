import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/app_shell.dart';
import '../../app/preview_controller.dart';
import '../../data/phase2_samples.dart';
import '../../models/backend_models.dart';
import '../../models/community_models.dart';
import '../../models/preview_models.dart';
import '../../shared/design_system.dart';
import '../../shared/park_art.dart';
import 'community_ui.dart';
import 'request_form.dart';
import 'attendance_views.dart';

List<ActivityRecord> visibleActivities(PreviewController c) =>
    c.session?.connected == true
    ? c.community?.activities ?? []
    : sampleActivities(c.demo.seededAt);
List<PlaceRecord> visiblePlaces(PreviewController c) =>
    c.session?.connected == true
    ? c.community?.places ?? []
    : samplePlaces(c.demo.seededAt);
DateTime communityNow(PreviewController c) =>
    c.session?.clock() ?? DateTime.now();

class CommunityActivities extends StatefulWidget {
  const CommunityActivities({super.key});
  @override
  State<CommunityActivities> createState() => _CommunityActivitiesState();
}

class _CommunityActivitiesState extends State<CommunityActivities> {
  int filter = 0;
  bool history = false;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    final live = c.session?.connected == true;
    final attendance = live && c.attendance != null;
    final now = communityNow(c);
    final wall = malaysiaWallTime(now);
    final week = DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
    ).subtract(Duration(days: wall.weekday - 1));
    final places = visiblePlaces(c);
    final activities = visibleActivities(c).where((a) {
      if (filter == 3 ? a.endsAt.isAfter(now) : !a.endsAt.isAfter(now)) {
        return false;
      }
      if (filter == 1) {
        final at = malaysiaWallTime(a.startsAt);
        return !at.isBefore(week) &&
            at.isBefore(week.add(const Duration(days: 7)));
      }
      if (filter == 2) {
        return places.where((p) => p.id == a.placeId).firstOrNull?.stepFree ==
            true;
      }
      return true;
    }).toList();
    if (history &&
        attendance &&
        (c.role == AppRole.elder || c.role == AppRole.family)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('back-to-activities'),
              onPressed: () => setState(() => history = false),
              icon: const Icon(Icons.arrow_back),
              label: Text(c.t('Browse activities', 'Lihat aktiviti')),
            ),
          ),
          const SizedBox(height: 16),
          const AttendanceHistory(),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommunityHeading(
          c.t(
            'Good things, close to home.',
            'Aktiviti menarik, dekat di rumah.',
          ),
          c.t(
            'A little movement, fresh air and familiar faces. Choose what feels right for your day.',
            'Nikmati senaman ringan, udara segar dan teman mesra. Pilih aktiviti yang sesuai untuk hari anda.',
          ),
          eyebrow: c.t('AROUND THE NEIGHBOURHOOD', 'SEKITAR KEJIRANAN'),
        ),
        if (!live) const SampleJourneyBanner(),
        if (attendance &&
            (c.role == AppRole.elder || c.role == AppRole.family)) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('open-attendance-history'),
              icon: const Icon(Icons.fact_check_outlined),
              onPressed: () => setState(() => history = true),
              label: Text(c.t('Attendance history', 'Sejarah kehadiran')),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 9,
          runSpacing: 8,
          children: [
            for (var i = 0; i < (attendance ? 4 : 3); i++)
              ChoiceChip(
                key: ValueKey('activity-filter-$i'),
                label: Text(
                  [
                    c.t('All activities', 'Semua aktiviti'),
                    c.t('This week', 'Minggu ini'),
                    c.t('Step-free', 'Tanpa tangga'),
                    c.t('Past activities', 'Aktiviti lalu'),
                  ][i],
                ),
                selected: filter == i,
                showCheckmark: false,
                onSelected: (_) => setState(() => filter = i),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (live && c.community?.catalogError != null)
          CommunityError(
            c.community!.catalogError!.message(c.malay),
            retry: c.community!.retry,
          )
        else if (live && c.community?.catalogLoading == true) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            c.t('Finding your local activities…', 'Mencari aktiviti setempat…'),
          ),
        ] else if (activities.isEmpty)
          PreviewEmpty(
            icon: Icons.calendar_today_outlined,
            title: c.t(
              'A little space in the calendar.',
              'Sedikit ruang dalam kalendar.',
            ),
            description: c.t(
              'No activities match this view. Try another filter or check back later.',
              'Tiada aktiviti sepadan dengan paparan ini. Cuba penapis lain atau semak kemudian.',
            ),
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              final columns = MediaQuery.textScalerOf(context).scale(1) > 1.15
                  ? 1
                  : box.maxWidth >= 1050
                  ? 3
                  : box.maxWidth >= 600
                  ? 2
                  : 1;
              final width = (box.maxWidth - (columns - 1) * 20) / columns;
              return Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  for (final a in activities)
                    SizedBox(
                      width: width,
                      child: _ActivityCard(
                        a,
                        places.where((p) => p.id == a.placeId).firstOrNull,
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 22),
        Text(
          live
              ? c.t(
                  'Catalog records come from your township’s local backend. Demo places and access notes are illustrative; check current conditions.',
                  'Rekod katalog datang dari pelayan setempat perbandaran anda. Tempat demo dan nota akses ialah contoh; semak keadaan semasa.',
                )
              : c.t(
                  'Sample activities and dates for exploring the interface.',
                  'Aktiviti dan tarikh contoh untuk meneroka antara muka.',
                ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard(this.activity, this.place);
  final ActivityRecord activity;
  final PlaceRecord? place;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), a = activity;
    final notice = place?.notice;
    return Semantics(
      button: true,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('activity-${a.id}'),
          onTap: () => openActivity(context, a),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 155,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ParkArt(garden: a.placeId.contains('garden')),
                    Positioned(
                      top: 14,
                      left: 14,
                      child: Pill(activityDate(a.startsAt, c.malay)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${malaysiaTime(a.startsAt)}–${malaysiaTime(a.endsAt)} MYT · ${a.language.toUpperCase()}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Palette.gold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      a.title.inLanguage(c.malay),
                      style: const TextStyle(
                        fontSize: 21,
                        height: 1.3,
                        letterSpacing: -.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      place?.name ??
                          c.t(
                            'Place details unavailable',
                            'Butiran tempat tidak tersedia',
                          ),
                      style: const TextStyle(
                        color: Palette.muted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        Pill(
                          place?.stepFree == true
                              ? c.t('Step-free', 'Tanpa tangga')
                              : c.t('Check access', 'Semak akses'),
                          icon: Icons.accessible_forward,
                        ),
                        if (place?.walkMinutes != null)
                          Pill(
                            c.t(
                              '${place!.walkMinutes} min walk',
                              '${place!.walkMinutes} min jalan',
                            ),
                            icon: Icons.directions_walk,
                          ),
                      ],
                    ),
                    if (notice != null) ...[
                      const SizedBox(height: 14),
                      Pill(
                        notice.activeAt(communityNow(c))
                            ? c.t('Place notice', 'Notis tempat')
                            : c.t(
                                'Needs coordinator review',
                                'Perlu semakan penyelaras',
                              ),
                        gold: true,
                        icon: Icons.info_outline,
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.t(
                              'View activity & access',
                              'Lihat aktiviti & akses',
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Palette.green,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward,
                          size: 18,
                          color: Palette.green,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void openActivity(BuildContext context, ActivityRecord activity) {
  final c = PreviewScope.of(context);
  showEmasSheet(
    context,
    CommunitySheetGuard(
      token: scopeToken(c),
      child: _ActivityDetail(activity.id),
    ),
  );
}

class _ActivityDetail extends StatefulWidget {
  const _ActivityDetail(this.id);
  final String id;
  @override
  State<_ActivityDetail> createState() => _ActivityDetailState();
}

class _ActivityDetailState extends State<_ActivityDetail> {
  bool request = false;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    final a = visibleActivities(c).where((a) => a.id == widget.id).firstOrNull;
    if (a == null) {
      return CommunityError(
        c.t(
          'This activity is no longer available.',
          'Aktiviti ini tidak lagi tersedia.',
        ),
      );
    }
    final place = visiblePlaces(c).where((p) => p.id == a.placeId).firstOrNull;
    if (request) {
      return CompanionRequestForm(
        activity: a,
        place: place,
        onBack: () => setState(() => request = false),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 180,
            child: ParkArt(garden: a.placeId.contains('garden')),
          ),
        ),
        const SizedBox(height: 22),
        Align(
          alignment: Alignment.centerLeft,
          child: Pill(
            c.session?.connected == true
                ? c.t('Local catalog', 'Katalog setempat')
                : c.t('Sample activity', 'Aktiviti contoh'),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          a.title.inLanguage(c.malay),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(
          '${activityDate(a.startsAt, c.malay)} · ${malaysiaTime(a.startsAt)}–${malaysiaTime(a.endsAt)} MYT',
        ),
        const SizedBox(height: 8),
        Text(
          c.t(
            'Language: ${a.language.toUpperCase()}',
            'Bahasa: ${a.language.toUpperCase()}',
          ),
          style: const TextStyle(color: Palette.muted),
        ),
        if (c.session?.connected == true && c.attendance != null)
          AttendanceActionPanel(a),
        const Divider(),
        if (place != null)
          PlaceAccessDetails(place)
        else
          Text(
            c.t(
              'Place and access details are not available yet. Check with the coordinator before making plans.',
              'Butiran tempat dan akses belum tersedia. Semak dengan penyelaras sebelum membuat rancangan.',
            ),
          ),
        const SizedBox(height: 24),
        if (c.role == AppRole.elder)
          EmasButton(
            label: c.session?.connected == true && c.sessions == null
                ? c.t(
                    'Preview a companion request',
                    'Pratonton permintaan teman',
                  )
                : c.t('Request a companion', 'Minta teman'),
            icon: Icons.people_outline,
            onPressed:
                (c.session?.connected == true && c.sessions != null
                    ? a.startsAt.isAfter(communityNow(c)) &&
                          a.participationMode == 'in_person'
                    : a.endsAt.isAfter(communityNow(c)))
                ? () => setState(() => request = true)
                : null,
          ),
        if (c.session?.connected == true &&
            c.sessions != null &&
            (!a.startsAt.isAfter(communityNow(c)) ||
                a.participationMode != 'in_person'))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              c.t(
                'Companion requests must be arranged before an in-person activity starts.',
                'Permintaan teman mesti diatur sebelum aktiviti bersemuka bermula.',
              ),
            ),
          ),
      ],
    );
  }
}

class PlaceAccessDetails extends StatelessWidget {
  const PlaceAccessDetails(this.place, {super.key});
  final PlaceRecord place;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), p = place;
    final notice = p.notice;
    String state(bool? v) => v == null
        ? c.t('Not recorded', 'Belum direkod')
        : v
        ? c.t('Available', 'Tersedia')
        : c.t('Not available', 'Tidak tersedia');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          c.t('A more comfortable way there', 'Perjalanan yang lebih selesa'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        Text(p.name, style: const TextStyle(color: Palette.muted)),
        const SizedBox(height: 18),
        for (final (label, icon, value) in [
          (
            c.t('Step-free entry', 'Laluan tanpa tangga'),
            Icons.accessible_forward,
            p.stepFree,
          ),
          (
            c.t('Accessible toilet', 'Tandas mesra akses'),
            Icons.wc_outlined,
            p.toilet,
          ),
          (
            c.t('Places to sit', 'Tempat duduk'),
            Icons.chair_outlined,
            p.seating,
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 21, color: Palette.green),
                const SizedBox(width: 12),
                Expanded(child: Text(label)),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    state(value),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: value == true ? Palette.green : Palette.muted,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Text(
          p.walkMinutes == null
              ? c.t('Walking time not recorded', 'Masa berjalan belum direkod')
              : c.t(
                  'About ${p.walkMinutes} minutes on foot',
                  'Kira-kira ${p.walkMinutes} minit berjalan kaki',
                ),
          style: const TextStyle(color: Palette.muted),
        ),
        if (p.notes.inLanguage(c.malay).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(p.notes.inLanguage(c.malay)),
          ),
        if (notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Surface(
              color: Palette.sand,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Palette.gold,
                        size: 20,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          notice.activeAt(communityNow(c))
                              ? c.t('Place notice', 'Notis tempat')
                              : c.t(
                                  'Needs coordinator review',
                                  'Perlu semakan penyelaras',
                                ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Palette.gold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(notice.text.inLanguage(c.malay)),
                  if (!notice.activeAt(communityNow(c)))
                    Text(
                      c.t(
                        'Expiry does not mean the place is safe. Ask the coordinator to review.',
                        'Tamat tempoh tidak bermakna tempat selamat. Minta penyelaras menyemak.',
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    notice.expiresAt == null
                        ? c.t(
                            'Expiry not recorded; ask the coordinator.',
                            'Tamat tempoh belum direkod; tanya penyelaras.',
                          )
                        : c.t(
                            'Until ${activityDate(notice.expiresAt!, c.malay)} · ${malaysiaTime(notice.expiresAt)} MYT',
                            'Sehingga ${activityDate(notice.expiresAt!, c.malay)} · ${malaysiaTime(notice.expiresAt)} MYT',
                          ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
        EmasButton(
          label: c.t('Open Maps', 'Buka Peta'),
          secondary: true,
          icon: Icons.open_in_new,
          onPressed: p.mapsLink == null
              ? null
              : () async {
                  var opened = false;
                  try {
                    opened = await launchUrl(
                      p.mapsLink!,
                      mode: LaunchMode.externalApplication,
                      webOnlyWindowName: '_blank',
                    );
                  } catch (_) {
                    opened = false;
                  }
                  if (!opened && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          c.t(
                            'Maps could not open. Please try again.',
                            'Peta tidak dapat dibuka. Sila cuba lagi.',
                          ),
                        ),
                      ),
                    );
                  }
                },
        ),
        const SizedBox(height: 12),
        Text(
          c.t(
            'Access notes are illustrative. Maps opens separately; check current conditions before leaving.',
            'Nota akses ialah contoh. Peta dibuka secara berasingan; semak keadaan semasa sebelum keluar.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class CommunityPlaces extends StatelessWidget {
  const CommunityPlaces({super.key});
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    final live = c.session?.connected == true;
    final places = visiblePlaces(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommunityHeading(
          c.t(
            'Places, with a little care.',
            'Tempat, dengan sedikit perhatian.',
          ),
          c.t(
            'Access details and current recorded notices for your township.',
            'Butiran akses dan notis direkodkan semasa bagi perbandaran anda.',
          ),
        ),
        if (!live) const SampleJourneyBanner(),
        if (live && c.community?.catalogError != null)
          CommunityError(
            c.community!.catalogError!.message(c.malay),
            retry: c.community!.retry,
          )
        else if (live && c.community?.catalogLoading == true)
          const LinearProgressIndicator()
        else if (places.isEmpty)
          PreviewEmpty(
            icon: Icons.place_outlined,
            title: c.t('No places recorded yet', 'Belum ada tempat direkodkan'),
            description: c.t(
              'Recorded places will appear here.',
              'Tempat yang direkodkan akan dipaparkan di sini.',
            ),
          )
        else
          for (final p in places)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Surface(child: PlaceAccessDetails(p)),
            ),
        if (live)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              c.t(
                'Place updates are not connected yet.',
                'Kemas kini tempat belum disambungkan.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

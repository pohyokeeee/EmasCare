import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/preview_models.dart';
import '../shared/design_system.dart';
import '../features/role_views.dart';
import 'preview_controller.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    return Scaffold(
      extendBody: true,
      bottomNavigationBar: wide
          ? null
          : Frosted(
              solid: c.solidNavigation || MediaQuery.highContrastOf(context),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      for (final d in Destination.values)
                        Expanded(child: _NavItem(d, compact: true)),
                    ],
                  ),
                ),
              ),
            ),
      body: Row(
        children: [
          if (wide) const SizedBox(width: 224, child: _Sidebar()),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    key: PageStorageKey('${c.role.name}-${c.destination.name}'),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1260),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            wide ? 38 : 20,
                            (wide
                                    ? 112
                                    : c.largeText
                                    ? 168
                                    : 144) +
                                MediaQuery.paddingOf(context).top,
                            wide ? 38 : 20,
                            wide ? 30 : 150,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const RoleContent(),
                              const SizedBox(height: 30),
                              Text(
                                c.session?.connected == true
                                    ? c.t(
                                        'Local Firebase demo · Your permitted records save on this emulator. Coordinators review reports and place warnings; check current conditions before visiting.',
                                        'Demo Firebase setempat · Rekod yang dibenarkan disimpan pada emulator ini. Penyelaras menyemak laporan dan amaran tempat; semak keadaan semasa sebelum berkunjung.',
                                      )
                                    : c.t(
                                        'Design preview · Sample people, places and progress. Changes reset on reload.',
                                        'Pratonton reka bentuk · Ahli, tempat dan kemajuan contoh. Muat semula untuk menetapkan semula.',
                                      ),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Frosted(
                    solid:
                        c.solidNavigation || MediaQuery.highContrastOf(context),
                    child: SafeArea(bottom: false, child: _Toolbar(wide: wide)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({this.small = false});
  final bool small;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: small ? 32 : 38,
        height: small ? 32 : 38,
        decoration: BoxDecoration(
          color: Palette.green,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          CupertinoIcons.leaf_arrow_circlepath,
          color: Colors.white,
          size: 22,
        ),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EmasCare',
              style: TextStyle(
                fontSize: small ? 19 : 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -.8,
                color: Palette.ink,
              ),
            ),
            if (!small)
              const Text(
                'TEMAN SIANG',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 2,
                  color: Palette.muted,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    return ColoredBox(
      color: const Color(0xFFFCFCF9),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(padding: EdgeInsets.only(left: 8), child: _Brand()),
              const SizedBox(height: 44),
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 13),
                child: Text(
                  c.t('YOUR EVERYDAY', 'HARI ANDA'),
                  style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.7,
                    color: Palette.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final d in Destination.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: _NavItem(d),
                ),
              const Spacer(),
              Surface(
                padding: const EdgeInsets.all(17),
                color: Palette.soft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      CupertinoIcons.sun_max,
                      color: Palette.green,
                      size: 24,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      c.t(
                        'Good days start\nwith a little company.',
                        'Hari indah bermula\ndengan seorang teman.',
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      c.session?.connected == true
                          ? c.session!.profile!.townshipId
                          : 'City of Elmina',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => showSettings(context),
                icon: const Icon(CupertinoIcons.slider_horizontal_3, size: 18),
                label: Text(c.t('Preferences', 'Keutamaan')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData navIcon(Destination d) => switch (d) {
  Destination.today => CupertinoIcons.house,
  Destination.activities => CupertinoIcons.calendar,
  Destination.companion => CupertinoIcons.person_2,
  Destination.rewards => CupertinoIcons.gift,
};

class _NavItem extends StatelessWidget {
  const _NavItem(this.destination, {this.compact = false});
  final Destination destination;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    final active = c.destination == destination;
    final icon = Icon(
      navIcon(destination),
      size: 22,
      color: active ? Palette.green : Palette.muted,
    );
    final text = Text(
      c.navName(destination),
      textAlign: compact ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        fontSize: compact ? 10 : 14,
        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        color: active ? Palette.green : Palette.muted,
      ),
    );
    return Semantics(
      selected: active,
      button: true,
      child: Material(
        color: active ? Palette.soft : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          key: ValueKey('nav-${destination.name}'),
          onTap: () => c.navigate(destination: destination),
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 4 : 13,
              vertical: compact ? 9 : 15,
            ),
            child: compact
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [icon, const SizedBox(height: 5), text],
                  )
                : Row(
                    children: [
                      icon,
                      const SizedBox(width: 12),
                      Expanded(child: text),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.wide});
  final bool wide;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: wide ? 38 : 16,
        vertical: wide ? 20 : 12,
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (wide)
                TextButton.icon(
                  onPressed: () => showSdpEntry(context),
                  icon: const Icon(
                    CupertinoIcons.square_grid_2x2,
                    size: 16,
                    color: Palette.muted,
                  ),
                  label: const Text(
                    'SDP home  /  EmasCare',
                    style: TextStyle(fontSize: 12, color: Palette.muted),
                  ),
                )
              else
                const Expanded(child: _Brand(small: true)),
              if (wide) const Spacer(),
              if (wide)
                TextButton(
                  onPressed: () => showPreviewInfo(context),
                  child: Pill(
                    c.session?.connected == true
                        ? c.t('Local backend', 'Pelayan setempat')
                        : c.t('Design preview', 'Pratonton reka bentuk'),
                    icon: CupertinoIcons.circle_grid_3x3,
                  ),
                ),
              TextButton(
                key: const ValueKey('language-toggle'),
                onPressed: c.toggleLanguage,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: Text(
                  c.malay ? 'EN' : 'BM',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('preferences'),
                tooltip: c.t('Preferences', 'Keutamaan'),
                onPressed: () => showSettings(context),
                icon: const Icon(CupertinoIcons.slider_horizontal_3, size: 20),
              ),
              if (wide) const SizedBox(width: 10),
              if (c.session != null) const _AccountMenu(),
              if (wide && c.session?.connected != true)
                PopupMenuButton<AppRole>(
                  key: const ValueKey('role-selector'),
                  tooltip: c.t(
                    'Switch preview role',
                    'Tukar peranan pratonton',
                  ),
                  onSelected: (r) => c.navigate(role: r),
                  itemBuilder: (_) => [
                    for (final r in AppRole.values)
                      PopupMenuItem(value: r, child: Text(c.roleName(r))),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Avatar(switch (c.role) {
                          AppRole.elder => 'MT',
                          AppRole.family => 'DL',
                          AppRole.helper => 'KL',
                          AppRole.coordinator => 'AN',
                        }, size: 36),
                        if (wide) ...[
                          const SizedBox(width: 9),
                          Text(
                            c.roleName(c.role),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(CupertinoIcons.chevron_down, size: 12),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (!wide)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => showPreviewInfo(context),
                      child: Text(
                        c.session?.connected == true
                            ? '${c.roleName(c.role)} · ${c.t("Local backend", "Pelayan setempat")}'
                            : c.t('Design preview', 'Pratonton reka bentuk'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Palette.muted,
                        ),
                      ),
                    ),
                  ),
                  if (c.session?.connected != true)
                    SizedBox(
                      width: 140,
                      child: PopupMenuButton<AppRole>(
                        key: const ValueKey('role-selector'),
                        tooltip: c.t(
                          'Switch preview role',
                          'Tukar peranan pratonton',
                        ),
                        onSelected: (r) => c.navigate(role: r),
                        itemBuilder: (_) => [
                          for (final r in AppRole.values)
                            PopupMenuItem(value: r, child: Text(c.roleName(r))),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              const Icon(
                                CupertinoIcons.person_crop_circle,
                                size: 24,
                                color: Palette.green,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  c.roleName(c.role),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Palette.green,
                                  ),
                                ),
                              ),
                              const Icon(
                                CupertinoIcons.chevron_down,
                                size: 10,
                                color: Palette.green,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), s = c.session!;
    return PopupMenuButton<String>(
      tooltip: c.t('Account', 'Akaun'),
      icon: const Icon(CupertinoIcons.person_crop_circle),
      enabled: !s.authBusy,
      onSelected: (value) {
        if (value == 'preview') s.signOut(enterPreview: true);
        if (value == 'out') s.signOut();
        if (value == 'in') s.leavePreview();
      },
      itemBuilder: (_) => s.connected
          ? [
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  '${s.profile!.displayName} · ${c.roleName(c.role)}',
                ),
              ),
              PopupMenuItem(
                value: 'out',
                child: Text(c.t('Sign out', 'Log keluar')),
              ),
              PopupMenuItem(
                value: 'preview',
                child: Text(
                  c.t('Open design preview', 'Buka pratonton reka bentuk'),
                ),
              ),
            ]
          : [
              PopupMenuItem(
                value: 'in',
                child: Text(c.t('Back to sign in', 'Kembali ke log masuk')),
              ),
            ],
    );
  }
}

Future<void> showEmasSheet(BuildContext context, Widget child) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 620),
    sheetAnimationStyle: reduced ? AnimationStyle.noAnimation : null,
    builder: (context) => Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Spacer(),
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Palette.line,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: PreviewScope.of(context).t('Close', 'Tutup'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(CupertinoIcons.xmark, size: 18),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    ),
  );
}

void showSettings(BuildContext context) =>
    showEmasSheet(context, const _Preferences());

class _Preferences extends StatelessWidget {
  const _Preferences();
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          c.t('Make yourself comfortable', 'Untuk keselesaan anda'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          c.t(
            'Your preferences apply to this tab.',
            'Keutamaan anda digunakan dalam tab ini.',
          ),
          style: const TextStyle(color: Palette.muted),
        ),
        const SizedBox(height: 18),
        _Preference(
          c.t('Larger text', 'Teks lebih besar'),
          c.largeText,
          (v) => c.setPreferences(text: v),
          key: const ValueKey('large-text'),
        ),
        _Preference(
          c.t('Gentler motion', 'Kurangkan gerakan'),
          c.reducedMotion,
          (v) => c.setPreferences(motion: v),
        ),
        _Preference(
          c.t('Solid navigation', 'Navigasi legap'),
          c.solidNavigation,
          (v) => c.setPreferences(solid: v),
        ),
        const Divider(),
        Text(
          c.t('Teman voice · device check', 'Suara Teman · semakan peranti'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          c.t(
            'Try a short recording and spoken read-back on your device. Audio stays in this tab; it is never uploaded. AI booking comes later.',
            'Cuba rakaman pendek dan bacaan suara pada peranti anda. Audio kekal dalam tab ini dan tidak dimuat naik. Tempahan AI akan datang.',
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            EmasButton(
              label: c.t('Check browser', 'Semak pelayar'),
              secondary: true,
              onPressed: c.browserBusy ? null : () => c.inspectBrowser('check'),
            ),
            EmasButton(
              label: c.browserBusy
                  ? c.t('Please wait…', 'Sila tunggu…')
                  : c.t('Record 5 seconds', 'Rakam 5 saat'),
              icon: CupertinoIcons.mic,
              onPressed: c.browserBusy
                  ? null
                  : () => c.inspectBrowser('record'),
            ),
            EmasButton(
              label: c.t('Play recording', 'Mainkan rakaman'),
              secondary: true,
              onPressed: c.browserBusy || c.browser?['recorded'] != true
                  ? null
                  : () => c.inspectBrowser('play'),
            ),
            EmasButton(
              label: c.t('Test spoken read-back', 'Uji bacaan suara'),
              secondary: true,
              onPressed: c.browserBusy
                  ? null
                  : () => c.inspectBrowser(c.malay ? 'speak-bm' : 'speak-en'),
            ),
          ],
        ),
        if (c.browser != null) ...[
          const SizedBox(height: 18),
          Surface(
            padding: const EdgeInsets.all(16),
            color: Palette.canvas,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.browser?['message']?.toString() ??
                      c.t('Browser checked.', 'Pelayar disemak.'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (c.browser?['error'] != true) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${c.t('Secure context', 'Konteks selamat')}: ${c.browser!['secure']}\n${c.t('Recording API', 'API rakaman')}: ${c.browser!['microphone']}\n${c.t('Speech playback API', 'API bacaan suara')}: ${c.browser!['speech']}\n${c.t('Microphone permission', 'Kebenaran mikrofon')}: ${c.browser!['permission']}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        TextButton(
          onPressed: () {
            c.resetPreview();
            Navigator.pop(context);
          },
          child: Text(
            c.t(
              'Reset sample check-in, availability & requests',
              'Tetap semula daftar masuk, ketersediaan & permintaan contoh',
            ),
          ),
        ),
      ],
    );
  }
}

class _Preference extends StatelessWidget {
  const _Preference(this.label, this.value, this.onChanged, {super.key});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 10),
        Semantics(
          label: label,
          child: CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: Palette.green,
          ),
        ),
      ],
    ),
  );
}

void showPreviewInfo(BuildContext context) {
  final c = PreviewScope.of(context);
  showEmasSheet(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          c.session?.connected == true
              ? c.t(
                  'Your connected local demo',
                  'Demo setempat tersambung anda',
                )
              : c.t('A first look at EmasCare', 'Pratonton pertama EmasCare'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 14),
        Text(
          c.session?.connected == true
              ? c.t(
                  'Sign-in, check-ins, consent settings, permitted family status and coordinator phone reports use your local Firebase emulators. Your role comes from your server profile.',
                  'Log masuk, daftar masuk, tetapan kebenaran, status keluarga yang dibenarkan dan laporan telefon penyelaras menggunakan emulator Firebase setempat. Peranan anda datang daripada profil pelayan.',
                )
              : c.t(
                  'Explore four roles, activities and a sample companion journey: request, assignment, session and separate participant confirmations. Sample changes stay in this tab and disappear on reload.',
                  'Terokai empat peranan, aktiviti dan perjalanan teman contoh: permintaan, penugasan, sesi dan pengesahan peserta berasingan. Perubahan contoh kekal dalam tab ini dan hilang apabila dimuat semula.',
                ),
        ),
        const SizedBox(height: 14),
        Text(
          c.t(
            'Sign in to the local demo for saved check-ins, consent, companion requests and session confirmations. Coin awards and redemption are pending. No messages are sent.',
            'Log masuk ke demo setempat untuk daftar masuk, kebenaran, permintaan teman dan pengesahan sesi tersimpan. Pemberian syiling dan penebusan belum tersedia. Tiada mesej dihantar.',
          ),
        ),
        const SizedBox(height: 22),
        EmasButton(
          label: c.t('Keep exploring', 'Teruskan meneroka'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
  );
}

void showSdpEntry(BuildContext context) {
  final c = PreviewScope.of(context);
  showEmasSheet(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IconTile(CupertinoIcons.square_grid_2x2),
        const SizedBox(height: 18),
        Text(
          c.t('Your neighbourhood, connected', 'Kejiranan anda, terhubung'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(
          c.t(
            'Mock SDP module entry. Real SDP integration is future work.',
            'Pintu masuk modul SDP contoh. Integrasi SDP sebenar akan datang.',
          ),
        ),
        const SizedBox(height: 20),
        EmasButton(
          label: c.t('Open EmasCare', 'Buka EmasCare'),
          onPressed: () {
            c.navigate(role: AppRole.elder);
            Navigator.pop(context);
          },
        ),
      ],
    ),
  );
}

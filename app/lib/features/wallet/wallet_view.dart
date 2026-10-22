import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../app/app_shell.dart';
import '../../app/preview_controller.dart';
import '../../models/wallet_models.dart';
import '../../models/backend_models.dart';
import '../../shared/design_system.dart';
import '../community/community_ui.dart';
import '../../models/community_models.dart';

String whenLabel(DateTime time, bool bm) =>
    '${activityDate(time, bm)} ${malaysiaWallTime(time).year} · ${malaysiaTime(time)} MYT';

String rewardLabel(RewardOutcome outcome, bool bm) => switch (outcome) {
  RewardOutcome.pendingPolicy =>
    bm ? 'Menunggu dasar ganjaran' : 'Awaiting reward policy',
  RewardOutcome.credited => bm ? 'Syiling dikreditkan' : 'Coins credited',
  RewardOutcome.ineligible =>
    bm ? 'Tidak layak untuk syiling' : 'Not eligible for coins',
};

class WalletView extends StatelessWidget {
  const WalletView({super.key});
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.wallet!;
    if (w.error != null) {
      return CommunityError(w.error!.message(c.malay), retry: w.retry);
    }
    if (w.loading) {
      return Column(
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            c.t(
              'Loading your saved wallet…',
              'Memuatkan dompet tersimpan anda…',
            ),
          ),
        ],
      );
    }
    final wallet = w.wallet;
    if (wallet == null) {
      return PreviewEmpty(
        icon: CupertinoIcons.lock,
        title: c.t('Your wallet is private.', 'Dompet anda adalah peribadi.'),
        description: c.t(
          'Only an elder or helper can open their own wallet.',
          'Hanya warga emas atau pembantu boleh membuka dompet sendiri.',
        ),
      );
    }
    final coins = Surface(
      color: Palette.green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.t('YOUR COINS', 'SYILING ANDA'),
            style: const TextStyle(
              color: Color(0xFFDCE8DA),
              fontSize: 11,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              '${wallet.balance}',
              key: const ValueKey('wallet-balance'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 54,
                height: 1.15,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            c.t('Available to use', 'Boleh digunakan'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            c.t(
              'Saved · ${whenLabel(wallet.updatedAt, c.malay)}',
              'Disimpan · ${whenLabel(wallet.updatedAt, c.malay)}',
            ),
            style: const TextStyle(color: Color(0xFFDCE8DA)),
          ),
        ],
      ),
    );
    final catalog = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          c.t('A little something in return', 'Sedikit ganjaran untuk anda'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (w.vouchers.isEmpty)
          _WalletEmpty(
            c.t('No demo vouchers available.', 'Tiada baucar demo tersedia.'),
          ),
        for (final voucher in w.vouchers)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: IconTile(CupertinoIcons.gift, gold: true),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    voucher.name(c.malay),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Pill(
                        c.t(
                          '${voucher.costCoins} coins',
                          '${voucher.costCoins} syiling',
                        ),
                        gold: true,
                      ),
                      Pill(c.t('DEMO ONLY', 'DEMO SAHAJA')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    c.t(
                      'A mock voucher with a DEMO code. It has no cash value and cannot be used at a merchant.',
                      'Baucar contoh dengan kod DEMO. Tiada nilai tunai dan tidak boleh digunakan di kedai.',
                    ),
                  ),
                  if (wallet.balance < voucher.costCoins)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        c.t(
                          'You need ${voucher.costCoins - wallet.balance} more coins. Pending rewards are not a balance.',
                          'Anda memerlukan ${voucher.costCoins - wallet.balance} syiling lagi. Ganjaran tertunda bukan baki.',
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  EmasButton(
                    key: ValueKey('redeem-${voucher.id}'),
                    label: voucher.redeemable
                        ? c.t('Review demo redemption', 'Semak penebusan demo')
                        : c.t(
                            'Currently unavailable',
                            'Tidak tersedia sekarang',
                          ),
                    icon: CupertinoIcons.ticket,
                    onPressed: !voucher.redeemable || w.action != null
                        ? null
                        : () {
                            final token = w.viewToken;
                            showEmasSheet(
                              context,
                              _WalletSheetGuard(
                                token: token,
                                child: _RedemptionReview(voucherId: voucher.id),
                              ),
                            );
                          },
                  ),
                ],
              ),
            ),
          ),
        const _PurchaseFeedback(),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommunityHeading(
          c.t(
            'Little moments, appreciated.',
            'Detik kecil, besar penghargaan.',
          ),
          c.t(
            'Your saved coins, participation rewards and demo vouchers, in one place.',
            'Syiling tersimpan, ganjaran penyertaan dan baucar demo anda, di satu tempat.',
          ),
        ),
        LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 880 && !c.largeText
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: coins),
                    const SizedBox(width: 24),
                    Expanded(flex: 5, child: catalog),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [coins, const SizedBox(height: 24), catalog],
                ),
        ),
        const SizedBox(height: 16),
        Surface(
          color: Palette.soft,
          child: Text(
            c.t(
              'Pending rewards do not add to your balance. Only eligible rewards under an approved rule add coins after verification.',
              'Ganjaran tertunda tidak menambah baki anda. Hanya ganjaran layak mengikut peraturan diluluskan menambah syiling selepas pengesahan.',
            ),
          ),
        ),
        const SizedBox(height: 28),
        _WalletSection(
          title: c.t('Participation rewards', 'Ganjaran penyertaan'),
          empty: c.t(
            'No verified participation rewards yet. A completed, verified activity or session can create a reward record.',
            'Belum ada ganjaran penyertaan disahkan. Aktiviti atau sesi yang selesai dan disahkan boleh menghasilkan rekod ganjaran.',
          ),
          children: [
            for (final claim in w.claims)
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Pill(
                      rewardLabel(claim.outcome, c.malay),
                      gold: claim.outcome != RewardOutcome.credited,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      c.t('Verified participation', 'Penyertaan disahkan'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(whenLabel(claim.verifiedAt, c.malay)),
                    const SizedBox(height: 10),
                    Text(switch (claim.outcome) {
                      RewardOutcome.pendingPolicy => c.t(
                        'Recorded, awaiting an applicable approved reward rule. No coins have been added.',
                        'Direkodkan, menunggu peraturan ganjaran diluluskan yang terpakai. Tiada syiling ditambah.',
                      ),
                      RewardOutcome.credited => c.t(
                        '${claim.amountCoins} coins added to your wallet.',
                        '${claim.amountCoins} syiling ditambah ke dompet anda.',
                      ),
                      RewardOutcome.ineligible => c.t(
                        'This participation does not earn coins under its approved rule.',
                        'Penyertaan ini tidak menerima syiling mengikut peraturan yang diluluskan.',
                      ),
                    }),
                  ],
                ),
              ),
          ],
        ),
        _WalletSection(
          title: c.t('Coin history', 'Sejarah syiling'),
          empty: c.t(
            'No coin transactions yet.',
            'Belum ada transaksi syiling.',
          ),
          children: [
            for (final entry in w.entries)
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.type == 'completion_reward'
                          ? c.t('Participation reward', 'Ganjaran penyertaan')
                          : c.t(
                              'Demo voucher redemption',
                              'Penebusan baucar demo',
                            ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      c.t(
                        '${entry.amount > 0 ? "+" : ""}${entry.amount} coins · Balance after: ${entry.balanceAfter}',
                        '${entry.amount > 0 ? "+" : ""}${entry.amount} syiling · Baki selepas: ${entry.balanceAfter}',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(whenLabel(entry.createdAt, c.malay)),
                  ],
                ),
              ),
          ],
        ),
        _WalletSection(
          title: c.t('My demo vouchers', 'Baucar demo saya'),
          empty: c.t(
            'No demo vouchers issued yet.',
            'Belum ada baucar demo dikeluarkan.',
          ),
          children: [
            for (final redemption in w.redemptions)
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Pill(c.t('DEMO ONLY', 'DEMO SAHAJA'), gold: true),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      redemption.code,
                      key: ValueKey('voucher-code-${redemption.id}'),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      c.t(
                        '${redemption.costCoins} coins · ${whenLabel(redemption.issuedAt, c.malay)}',
                        '${redemption.costCoins} syiling · ${whenLabel(redemption.issuedAt, c.malay)}',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      c.t(
                        'Saved demo code. No merchant voucher is issued.',
                        'Kod demo tersimpan. Tiada baucar kedai dikeluarkan.',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _WalletEmpty extends StatelessWidget {
  const _WalletEmpty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Surface(child: Text(text));
}

class _WalletSection extends StatelessWidget {
  const _WalletSection({
    required this.title,
    required this.empty,
    required this.children,
  });
  final String title, empty;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        if (children.isEmpty) _WalletEmpty(empty),
        for (final child in children)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: child),
      ],
    ),
  );
}

class _WalletSheetGuard extends StatelessWidget {
  const _WalletSheetGuard({required this.token, required this.child});
  final String? token;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (token != null && PreviewScope.of(context).wallet?.viewToken == token) {
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

class _RedemptionReview extends StatelessWidget {
  const _RedemptionReview({required this.voucherId});
  final String voucherId;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.wallet!;
    final voucher = w.vouchers.where((v) => v.id == voucherId).firstOrNull;
    void closeIfCurrent() {
      if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
      }
    }

    if (voucher == null || !voucher.redeemable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WalletEmpty(
            w.action == null
                ? c.t(
                    'This voucher is no longer available. Close this sheet to check the catalogue.',
                    'Baucar ini tidak lagi tersedia. Tutup helaian ini untuk menyemak katalog.',
                  )
                : c.t(
                    'This voucher is unavailable for new purchases. You can retry your existing purchase below.',
                    'Baucar ini tidak tersedia untuk pembelian baharu. Anda boleh mencuba semula pembelian sedia ada di bawah.',
                  ),
          ),
          _PurchaseFeedback(showSaved: false, onSuccess: closeIfCurrent),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          c.t(
            'A small thank-you, for you.',
            'Sedikit penghargaan, untuk anda.',
          ),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 18),
        Text(
          voucher.name(c.malay),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Text(
          c.t(
            'Use ${voucher.costCoins} coins from your own wallet for one mock voucher.',
            'Gunakan ${voucher.costCoins} syiling daripada dompet sendiri untuk satu baucar contoh.',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          c.t(
            'Current saved balance: ${w.wallet?.balance ?? "—"} coins',
            'Baki tersimpan semasa: ${w.wallet?.balance ?? "—"} syiling',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          c.t(
            'This issues a DEMO code only. It cannot be spent at a merchant. The server will check your available balance before saving.',
            'Ini hanya mengeluarkan kod DEMO. Ia tidak boleh digunakan di kedai. Pelayan akan menyemak baki tersedia sebelum menyimpan.',
          ),
        ),
        const SizedBox(height: 24),
        EmasButton(
          key: const ValueKey('confirm-demo-redemption'),
          label: c.t('Confirm demo redemption', 'Sahkan penebusan demo'),
          icon: CupertinoIcons.ticket,
          onPressed: w.action != null
              ? null
              : () async {
                  final ok = await w.redeem(voucherId);
                  if (ok &&
                      context.mounted &&
                      ModalRoute.of(context)?.isCurrent == true) {
                    Navigator.pop(context);
                  }
                },
        ),
        _PurchaseFeedback(showSaved: false, onSuccess: closeIfCurrent),
      ],
    );
  }
}

class _PurchaseFeedback extends StatelessWidget {
  const _PurchaseFeedback({this.onSuccess, this.showSaved = true});
  final VoidCallback? onSuccess;
  final bool showSaved;
  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.wallet!;
    final action = w.action;
    if (action == null) {
      return !showSaved || w.savedRedemptionId == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  c.t(
                    'Demo redemption saved. Your saved vouchers and coin history update automatically.',
                    'Penebusan demo disimpan. Baucar tersimpan dan sejarah syiling dikemas kini secara automatik.',
                  ),
                ),
              ),
            );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: action.busy
          ? Column(
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 10),
                Text(
                  c.t('Saving your redemption…', 'Menyimpan penebusan anda…'),
                ),
              ],
            )
          : Surface(
              color: Palette.sand,
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
                  const SizedBox(height: 12),
                  Text(
                    c.t(
                      'A retry keeps the same voucher and purchase. It will not create a second debit.',
                      'Cubaan semula mengekalkan baucar dan pembelian yang sama. Ia tidak menghasilkan potongan kedua.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  EmasButton(
                    label: c.t(
                      'Retry same redemption',
                      'Cuba semula penebusan sama',
                    ),
                    secondary: true,
                    onPressed: () async {
                      if (await w.retryRedemption()) onSuccess?.call();
                    },
                  ),
                  TextButton(
                    onPressed: w.discard,
                    child: Text(
                      c.t(
                        'Stop retrying / choose again',
                        'Hentikan cubaan / pilih semula',
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

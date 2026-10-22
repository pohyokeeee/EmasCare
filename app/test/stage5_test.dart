import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:emas_care/app/emas_app.dart';
import 'package:emas_care/app/preview_controller.dart';
import 'package:emas_care/app/session_controller.dart';
import 'package:emas_care/app/wallet_controller.dart';
import 'package:emas_care/data/backend_failure.dart';
import 'package:emas_care/data/emas_repository.dart';
import 'package:emas_care/data/wallet_repository.dart';
import 'package:emas_care/models/backend_models.dart';
import 'package:emas_care/models/preview_models.dart';
import 'package:emas_care/models/wallet_models.dart';
import 'package:emas_care/shared/design_system.dart';
import 'stage4_test.dart' as stage4;
import 'backend_test.dart' as auth;

final fixture = jsonObject(
  jsonDecode(File('../docs/fixtures/stage5_wallet.json').readAsStringSync()),
);
final now = DateTime.utc(2026, 10, 22);
Json example([String role = 'elder']) =>
    jsonObject(jsonObject(fixture['isolatedRedemptionUiScenarios'])[role]);
Json resultJson([String role = 'elder']) =>
    jsonObject(jsonObject(example(role)['output'])['data']);
Json claimJson({String status = 'pending_policy', String uid = 'elder_demo'}) =>
    {
      'id': 'claim-$status',
      'beneficiaryUid': uid,
      'beneficiaryRole': uid.split('_').first,
      'townshipId': 'township_demo',
      'participationId': 'participation-$status',
      'completionEventId': 'event',
      'status': status,
      'eligible': status == 'pending_policy' ? null : status == 'credited',
      'amountCoins': status == 'pending_policy'
          ? null
          : status == 'credited'
          ? 100
          : 0,
      'rateCoins': status == 'credited' ? 100 : null,
      'ruleId': status == 'pending_policy' ? null : 'test-only-rule',
      'ruleVersion': status == 'pending_policy' ? null : 'test-only-version',
      'ledgerEntryId': status == 'credited' ? 'test-only-entry' : null,
      'reason': 'SYNTHETIC_UI_TEST_ONLY',
      'verifiedAt': now.toIso8601String(),
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    };

// Hypothetical funded states exist ONLY in this isolated UI fake, never seeded.
class WalletFake extends stage4.AttendanceFake implements WalletRepository {
  int balance = 0, cancels = 0;
  bool missing = false, active = true;
  final List<String> walletQueries = [];
  final List<(Json, String)> purchases = [];
  final List<RewardClaim> claims = [];
  final List<WalletEntry> entries = [];
  final List<VoucherRedemption> redemptions = [];
  Future<RedemptionResult> Function(Json, String)? purchase;
  late final walletEvents = StreamController<WalletRecord?>.broadcast(
    sync: true,
    onCancel: () => cancels++,
  );
  late final entryEvents = StreamController<List<WalletEntry>>.broadcast(
    sync: true,
    onCancel: () => cancels++,
  );
  late final claimEvents = StreamController<List<RewardClaim>>.broadcast(
    sync: true,
    onCancel: () => cancels++,
  );
  late final voucherEvents = StreamController<List<DemoVoucher>>.broadcast(
    sync: true,
    onCancel: () => cancels++,
  );
  late final redemptionEvents =
      StreamController<List<VoucherRedemption>>.broadcast(
        sync: true,
        onCancel: () => cancels++,
      );
  WalletRecord wallet({String? uid}) => WalletRecord.fromJson({
    'ownerUid': uid ?? current.uid,
    'townshipId': current.townshipId,
    'balance': balance,
    'updatedAt': now.toIso8601String(),
  });
  DemoVoucher voucher() => DemoVoucher.fromJson({
    'id': 'voucher_demo',
    'townshipId': current.townshipId,
    'title': {'en': 'Mock voucher', 'bm': 'Baucar contoh'},
    'costCoins': 100,
    'active': active,
    'isDemo': true,
  });
  void emitWallet() {
    walletEvents.add(missing ? null : wallet());
    entryEvents.add(List.of(entries));
    claimEvents.add(List.of(claims));
    voucherEvents.add([voucher()]);
    redemptionEvents.add(List.of(redemptions));
  }

  @override
  Stream<WalletRecord?> watchWallet(BackendProfile p) {
    walletQueries.add('wallet/${p.uid}/${p.role.name}/${p.townshipId}');
    return walletEvents.stream;
  }

  @override
  Stream<List<WalletEntry>> watchWalletEntries(BackendProfile p) {
    walletQueries.add('entries/${p.uid}/${p.townshipId}');
    return entryEvents.stream;
  }

  @override
  Stream<List<RewardClaim>> watchRewardClaims(BackendProfile p) {
    walletQueries.add('claims/${p.uid}/${p.townshipId}');
    return claimEvents.stream;
  }

  @override
  Stream<List<DemoVoucher>> watchVouchers(BackendProfile p) {
    walletQueries.add('vouchers/${p.townshipId}');
    return voucherEvents.stream;
  }

  @override
  Stream<List<VoucherRedemption>> watchRedemptions(BackendProfile p) {
    walletQueries.add('redemptions/${p.uid}/${p.townshipId}');
    return redemptionEvents.stream;
  }

  @override
  Future<RedemptionResult> redeemDemoVoucher(Json fields, String key) async {
    purchases.add((fields, key));
    if (purchase != null) return purchase!(fields, key);
    if (balance < 100) {
      throw const BackendFailure('failed-precondition', 'INSUFFICIENT_BALANCE');
    }
    balance -= 100;
    final result = RedemptionResult.fromJson(resultJson(current.role.name));
    redemptions.add(result.redemption);
    entries.add(
      WalletEntry.fromJson(
        jsonObject(example(current.role.name)['debitEntry']),
      ),
    );
    emitWallet();
    return result;
  }

  @override
  Future<void> close() async {
    await super.close();
    await Future.wait([
      walletEvents.close(),
      entryEvents.close(),
      claimEvents.close(),
      voucherEvents.close(),
      redemptionEvents.close(),
    ]);
  }
}

Future<void> sign(WalletFake f, SessionController s, AppRole role) async {
  await stage4.signAs(f, s, role);
  f.emitWallet();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('Manrope');
    for (final weight in [400, 500, 600, 700]) {
      fonts.addFont(rootBundle.load('assets/fonts/Manrope-$weight.ttf'));
    }
    await fonts.load();
  });
  test(
    'both published isolated redemption fixtures preserve exact fields and ISO/Firestore times',
    () {
      Object? timestamps(Object? value) => value is Map
          ? value.map((k, v) => MapEntry(k, timestamps(v)))
          : value is String && value.startsWith('2026-')
          ? Timestamp.fromDate(DateTime.parse(value))
          : value;
      for (final role in ['elder', 'helper']) {
        final data = resultJson(role),
            a = RedemptionResult.fromJson(data),
            b = RedemptionResult.fromJson(jsonObject(timestamps(data)));
        expect(a.entryId, data['entryId']);
        expect(a.balance, 0);
        expect(a.redemption.ownerUid, '${role}_demo');
        expect(a.redemption.costCoins, 100);
        expect(a.redemption.code, startsWith('DEMO-'));
        expect(a.redemption.isDemo, true);
        expect(a.redemption.issuedAt, b.redemption.issuedAt);
        final entry = WalletEntry.fromJson(
          jsonObject(example(role)['debitEntry']),
        );
        expect(entry.id, a.entryId);
        expect(entry.amount, -100);
        expect(entry.balanceAfter, 0);
        expect(entry.referenceId, a.redemption.id);
        expect(entry.participationId, isNull);
        expect(entry.ruleVersion, isNull);
        expect(entry.rateCoins, isNull);
      }
      for (final status in ['pending_policy', 'credited', 'ineligible']) {
        final row = claimJson(status: status),
            claim = RewardClaim.fromJson(row);
        expect(
          claim.verifiedAt,
          RewardClaim.fromJson(jsonObject(timestamps(row))).verifiedAt,
        );
        expect(claim.amountCoins, row['amountCoins']);
        expect(claim.reason, row['reason']);
      }
    },
  );
  test(
    'malformed money and pending claims pretending to be earned are rejected',
    () {
      for (final value in [-1, 0.5, 9007199254740992, '100', null]) {
        expect(() => coinInteger(value), throwsFormatException);
      }
      expect(
        () => RewardClaim.fromJson({...claimJson(), 'amountCoins': 100}),
        throwsFormatException,
      );
      expect(
        () => RedemptionResult.fromJson({...resultJson(), 'entryId': 'wrong'}),
        throwsFormatException,
      );
      expect(
        () => VoucherRedemption.fromJson({
          ...jsonObject(resultJson()['redemption']),
          'isDemo': false,
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'actual owner queries only; family/coordinator never subscribe; logout cancels and clears',
    () async {
      final f = WalletFake(),
          s = SessionController(f),
          w = WalletController(s, f);
      for (final role in [AppRole.family, AppRole.coordinator]) {
        await sign(f, s, role);
        expect(f.walletQueries, isEmpty);
        expect(await w.redeem('voucher_demo'), false);
        expect(w.wallet, isNull);
      }
      await sign(f, s, AppRole.elder);
      expect(w.wallet!.balance, 0);
      expect(f.walletQueries.length, 5);
      await s.signOut();
      expect(w.wallet, isNull);
      expect(w.claims, isEmpty);
      expect(w.viewToken, isNull);
      expect(f.cancels, 5);
      await sign(f, s, AppRole.helper);
      expect(w.wallet!.ownerUid, 'helper_demo');
      expect(f.walletQueries.length, 10);
      w.dispose();
      s.dispose();
      await f.close();
    },
  );
  test(
    'one purchase per confirmation, immutable retry key/payload, new intent gets a new key',
    () async {
      final f = WalletFake(),
          s = SessionController(f),
          w = WalletController(s, f);
      await sign(f, s, AppRole.elder);
      final delayed = Completer<RedemptionResult>();
      f.purchase = (_, _) => delayed.future;
      final pending = w.redeem('voucher_demo');
      expect(await w.redeem('another'), false);
      expect(f.purchases.length, 1);
      expect(
        () => w.action!.fields['voucherId'] = 'changed',
        throwsUnsupportedError,
      );
      delayed.completeError(const BackendFailure('unavailable'));
      expect(await pending, false);
      final oldKey = f.purchases.single.$2;
      f.purchase = (_, _) async => RedemptionResult.fromJson(resultJson());
      expect(await w.redeem('changed-voucher'), true);
      expect(f.purchases.last.$1, {'voucherId': 'voucher_demo'});
      expect(f.purchases.last.$2, oldKey);
      expect(await w.redeem('voucher_demo'), true);
      expect(f.purchases.last.$2, isNot(oldKey));
      w.dispose();
      s.dispose();
      await f.close();
    },
  );
  test(
    'late receipt balance never overwrites a newer wallet snapshot',
    () async {
      final f = WalletFake(),
          s = SessionController(f),
          w = WalletController(s, f);
      await sign(f, s, AppRole.elder);
      final delayed = Completer<RedemptionResult>();
      f.purchase = (_, _) => delayed.future;
      final pending = w.redeem('voucher_demo');
      f.balance = 200;
      f.emitWallet();
      delayed.complete(RedemptionResult.fromJson(resultJson()));
      expect(await pending, true);
      expect(w.wallet!.balance, 200);
      expect(w.savedRedemptionId, isNotNull);
      w.dispose();
      s.dispose();
      await f.close();
    },
  );
  test(
    'denied stream clears every private record and failed intent; retry rebinds without invented balance',
    () async {
      final f = WalletFake(),
          s = SessionController(f),
          w = WalletController(s, f);
      await sign(f, s, AppRole.elder);
      f.claims.add(RewardClaim.fromJson(claimJson()));
      f.emitWallet();
      expect(await w.redeem('voucher_demo'), false);
      expect(w.action!.error!.reason, 'INSUFFICIENT_BALANCE');
      f.entryEvents.addError(const BackendFailure('permission-denied'));
      expect(w.wallet, isNull);
      expect(w.claims, isEmpty);
      expect(w.action, isNull);
      expect(w.viewToken, isNull);
      expect(f.cancels, 5);
      w.retry();
      f.emitWallet();
      expect(w.error, isNull);
      expect(w.wallet!.balance, 0);
      f.missing = true;
      f.emitWallet();
      expect(w.wallet, isNull);
      expect(w.error!.reason, 'WALLET_REQUIRED');
      w.dispose();
      s.dispose();
      await f.close();
    },
  );
  test(
    'late purchase after logout or role change cannot show a prior owner receipt',
    () async {
      final f = WalletFake(),
          s = SessionController(f),
          w = WalletController(s, f);
      await sign(f, s, AppRole.elder);
      final delayed = Completer<RedemptionResult>();
      f.purchase = (_, _) => delayed.future;
      final pending = w.redeem('voucher_demo');
      await s.signOut();
      delayed.complete(RedemptionResult.fromJson(resultJson()));
      expect(await pending, false);
      expect(w.savedRedemptionId, isNull);
      expect(w.action, isNull);
      expect(w.wallet, isNull);
      w.dispose();
      s.dispose();
      await f.close();
    },
  );
  test(
    'cross-owner stream rows fail closed; financial access is independent of family consents',
    () async {
      final f = WalletFake(),
          s = SessionController(f),
          w = WalletController(s, f);
      await sign(f, s, AppRole.elder);
      final token = w.viewToken;
      f.settingsEvents.add(auth.settings(sharing: false, booking: false));
      expect(w.viewToken, token);
      f.claimEvents.add([RewardClaim.fromJson(claimJson(uid: 'helper_demo'))]);
      expect(w.wallet, isNull);
      expect(w.error!.reason, 'WALLET_ACCESS_DENIED');
      w.dispose();
      s.dispose();
      await f.close();
    },
  );

  Future<void> tap(WidgetTester t, Finder finder) async {
    final target = t.widget(finder) is EmasButton
        ? find.descendant(of: finder, matching: find.byType(Text)).first
        : finder;
    await Scrollable.ensureVisible(t.element(target), alignment: 0.5);
    await t.pumpAndSettle();
    await t.tap(target);
    await t.pumpAndSettle();
  }

  Future<void> login(
    WidgetTester t,
    WalletFake f,
    SessionController s,
    AppRole role,
  ) async {
    await t.runAsync(() => sign(f, s, role));
    f.emitCommunity();
    f.emitWallet();
    await t.pumpAndSettle();
  }

  Future<void> finish(
    WidgetTester t,
    PreviewController c,
    SessionController s,
    MockEmasRepository mock,
    WalletFake f,
  ) async {
    await t.pumpWidget(const SizedBox());
    c.dispose();
    s.dispose();
    mock.dispose();
    await f.close();
  }

  void desktop(WidgetTester t) {
    t.view.physicalSize = const Size(1440, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  testWidgets(
    'zero saved balance and pending claim stay honest; confirmed redemption shows insufficient balance',
    (t) async {
      desktop(t);
      final f = WalletFake(),
          s = SessionController(f),
          mock = MockEmasRepository(),
          c = PreviewController(mock, session: s);
      f.claims.add(RewardClaim.fromJson(claimJson()));
      await t.pumpWidget(EmasCareApp(controller: c));
      await login(t, f, s, AppRole.elder);
      c.navigate(destination: Destination.rewards);
      await t.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
      expect(find.text('Awaiting reward policy'), findsOneWidget);
      await tap(t, find.byKey(const ValueKey('redeem-voucher_demo')));
      expect(f.purchases, isEmpty);
      await tap(t, find.byKey(const ValueKey('confirm-demo-redemption')));
      expect(f.purchases.length, 1);
      expect(find.textContaining('Not enough coins.'), findsWidgets);
      expect(c.wallet!.wallet!.balance, 0);
      expect(c.wallet!.redemptions, isEmpty);
      await tap(t, find.byTooltip('Close'));
      await finish(t, c, s, mock, f);
    },
  );
  testWidgets(
    'isolated funded elder/helper confirmation saves code and debit, closes sheet and refreshes wallet',
    (t) async {
      desktop(t);
      for (final role in [AppRole.elder, AppRole.helper]) {
        final f = WalletFake()..balance = 100,
            s = SessionController(f),
            mock = MockEmasRepository(),
            c = PreviewController(mock, session: s);
        await t.pumpWidget(EmasCareApp(controller: c));
        await login(t, f, s, role);
        c.navigate(destination: Destination.rewards);
        await t.pumpAndSettle();
        await tap(t, find.byKey(const ValueKey('redeem-voucher_demo')));
        await tap(t, find.byKey(const ValueKey('confirm-demo-redemption')));
        expect(
          find.byKey(const ValueKey('confirm-demo-redemption')),
          findsNothing,
        );
        expect(c.wallet!.wallet!.balance, 0);
        expect(f.purchases.length, 1);
        expect(find.text(c.wallet!.redemptions.single.code), findsOneWidget);
        expect(find.text('-100 coins · Balance after: 0'), findsOneWidget);
        await finish(t, c, s, mock, f);
      }
    },
  );
  testWidgets(
    'dismissed busy purchase cannot navigate later; permission loss closes a confirmation',
    (t) async {
      desktop(t);
      final f = WalletFake(),
          s = SessionController(f),
          mock = MockEmasRepository(),
          c = PreviewController(mock, session: s);
      final delayed = Completer<RedemptionResult>();
      f.purchase = (_, _) => delayed.future;
      await t.pumpWidget(EmasCareApp(controller: c));
      await login(t, f, s, AppRole.elder);
      c.navigate(destination: Destination.rewards);
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('redeem-voucher_demo')));
      final confirm = find
          .descendant(
            of: find.byKey(const ValueKey('confirm-demo-redemption')),
            matching: find.byType(Text),
          )
          .first;
      await Scrollable.ensureVisible(t.element(confirm), alignment: 0.5);
      await t.pumpAndSettle();
      await t.tap(confirm);
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.byTooltip('Close'));
      await t.pump(const Duration(milliseconds: 500));
      c.navigate(destination: Destination.today);
      await t.pump(const Duration(milliseconds: 100));
      delayed.complete(RedemptionResult.fromJson(resultJson()));
      await t.pumpAndSettle();
      expect(find.text('How are you today?'), findsOneWidget);
      c.navigate(destination: Destination.rewards);
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('redeem-voucher_demo')));
      f.walletEvents.addError(const BackendFailure('permission-denied'));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('confirm-demo-redemption')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('wallet-balance')), findsNothing);
      await finish(t, c, s, mock, f);
    },
  );
  testWidgets(
    'BM and larger text fit wallet, outcomes, debit, code and purchase at 320/390/768/1440 widths',
    (t) async {
      for (final width in [320.0, 390.0, 768.0, 1440.0]) {
        t.view.physicalSize = Size(width, 1100);
        t.view.devicePixelRatio = 1;
        final f = WalletFake()..balance = 100,
            s = SessionController(f),
            mock = MockEmasRepository(),
            c = PreviewController(mock, session: s);
        f.claims.addAll([
          for (final status in ['pending_policy', 'credited', 'ineligible'])
            RewardClaim.fromJson(claimJson(status: status)),
        ]);
        f.redemptions.add(
          VoucherRedemption.fromJson(jsonObject(resultJson()['redemption'])),
        );
        f.entries.add(
          WalletEntry.fromJson(jsonObject(example()['debitEntry'])),
        );
        await t.pumpWidget(EmasCareApp(controller: c));
        await login(t, f, s, AppRole.elder);
        c.toggleLanguage();
        c.setPreferences(text: true, motion: true, solid: true);
        c.navigate(destination: Destination.rewards);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'wallet $width');
        await tap(t, find.byKey(const ValueKey('redeem-voucher_demo')));
        expect(t.takeException(), isNull, reason: 'confirmation $width');
        await tap(t, find.byTooltip('Tutup'));
        await finish(t, c, s, mock, f);
      }
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
}

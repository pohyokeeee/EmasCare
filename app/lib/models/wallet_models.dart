import 'backend_models.dart';

int coinInteger(Object? value, {bool signed = false}) {
  if (value is! int ||
      value > 9007199254740991 ||
      value < -9007199254740991 ||
      (!signed && value < 0)) {
    throw const FormatException('Invalid coin amount');
  }
  return value;
}

class WalletRecord {
  WalletRecord.fromJson(Json j)
    : ownerUid = j['ownerUid'] as String,
      townshipId = j['townshipId'] as String,
      balance = coinInteger(j['balance']),
      updatedAt = utcTimestamp(j['updatedAt'])!;
  final String ownerUid, townshipId;
  final int balance;
  final DateTime updatedAt;
}

enum RewardOutcome { pendingPolicy, credited, ineligible }

class RewardClaim {
  RewardClaim.fromJson(Json j)
    : id = j['id'] as String,
      beneficiaryUid = j['beneficiaryUid'] as String,
      beneficiaryRole = j['beneficiaryRole'] as String,
      townshipId = j['townshipId'] as String,
      participationId = j['participationId'] as String,
      completionEventId = j['completionEventId'] as String,
      outcome = switch (j['status']) {
        'pending_policy' => RewardOutcome.pendingPolicy,
        'credited' => RewardOutcome.credited,
        'ineligible' => RewardOutcome.ineligible,
        _ => throw const FormatException('Invalid reward outcome'),
      },
      eligible = j['eligible'] as bool?,
      amountCoins = j['amountCoins'] == null
          ? null
          : coinInteger(j['amountCoins']),
      rateCoins = j['rateCoins'] == null ? null : coinInteger(j['rateCoins']),
      ruleId = j['ruleId'] as String?,
      ruleVersion = j['ruleVersion'] as String?,
      ledgerEntryId = j['ledgerEntryId'] as String?,
      reason = j['reason'] as String?,
      verifiedAt = utcTimestamp(j['verifiedAt'])!,
      createdAt = utcTimestamp(j['createdAt'])!,
      updatedAt = utcTimestamp(j['updatedAt'])! {
    if ((outcome == RewardOutcome.pendingPolicy &&
            (eligible != null ||
                amountCoins != null ||
                rateCoins != null ||
                ledgerEntryId != null)) ||
        (outcome == RewardOutcome.credited &&
            (eligible != true ||
                amountCoins == null ||
                amountCoins! <= 0 ||
                rateCoins != amountCoins ||
                ledgerEntryId == null ||
                ruleId == null ||
                ruleVersion == null)) ||
        (outcome == RewardOutcome.ineligible &&
            (eligible != false || amountCoins != 0))) {
      throw const FormatException('Inconsistent reward outcome');
    }
  }
  final String id,
      beneficiaryUid,
      beneficiaryRole,
      townshipId,
      participationId,
      completionEventId;
  final RewardOutcome outcome;
  final bool? eligible;
  final int? amountCoins, rateCoins;
  final String? ruleId, ruleVersion, ledgerEntryId, reason;
  final DateTime verifiedAt, createdAt, updatedAt;
}

class WalletEntry {
  WalletEntry.fromJson(Json j)
    : id = j['id'] as String,
      ownerUid = j['ownerUid'] as String,
      townshipId = j['townshipId'] as String,
      type = j['type'] as String,
      amount = coinInteger(j['amount'], signed: true),
      balanceAfter = coinInteger(j['balanceAfter']),
      participationId = j['participationId'] as String?,
      completionEventId = j['completionEventId'] as String?,
      ruleId = j['ruleId'] as String?,
      ruleVersion = j['ruleVersion'] as String?,
      rateCoins = j['rateCoins'] == null ? null : coinInteger(j['rateCoins']),
      referenceId = j['referenceId'] as String,
      createdAt = utcTimestamp(j['createdAt'])! {
    if (!['completion_reward', 'voucher_redemption'].contains(type) ||
        (type == 'completion_reward' && amount <= 0) ||
        (type == 'voucher_redemption' && amount != -100)) {
      throw const FormatException('Inconsistent ledger entry');
    }
  }
  final String id, ownerUid, townshipId, type, referenceId;
  final int amount, balanceAfter;
  final String? participationId, completionEventId, ruleId, ruleVersion;
  final int? rateCoins;
  final DateTime createdAt;
}

class DemoVoucher {
  DemoVoucher.fromJson(Json j)
    : id = j['id'] as String,
      townshipId = j['townshipId'] as String,
      title = jsonObject(j['title']),
      costCoins = coinInteger(j['costCoins']),
      active = j['active'] == true,
      isDemo = j['isDemo'] == true;
  final String id, townshipId;
  final Json title;
  final int costCoins;
  final bool active, isDemo;
  bool get redeemable => active && isDemo && costCoins == 100;
  String name(bool bm) => title[bm ? 'bm' : 'en'] as String;
}

class VoucherRedemption {
  VoucherRedemption.fromJson(Json j)
    : id = j['id'] as String,
      ownerUid = j['ownerUid'] as String,
      townshipId = j['townshipId'] as String,
      voucherId = j['voucherId'] as String,
      costCoins = coinInteger(j['costCoins']),
      code = j['code'] as String,
      ledgerEntryId = j['ledgerEntryId'] as String,
      issuedAt = utcTimestamp(j['issuedAt'])!,
      isDemo = j['isDemo'] == true {
    if (!isDemo || !code.startsWith('DEMO-') || costCoins != 100) {
      throw const FormatException('Invalid demo redemption');
    }
  }
  final String id, ownerUid, townshipId, voucherId, code, ledgerEntryId;
  final int costCoins;
  final bool isDemo;
  final DateTime issuedAt;
}

class RedemptionResult {
  RedemptionResult.fromJson(Json j)
    : redemption = VoucherRedemption.fromJson(jsonObject(j['redemption'])),
      entryId = j['entryId'] as String,
      balance = coinInteger(j['balance']) {
    if (entryId != redemption.ledgerEntryId) {
      throw const FormatException('Invalid redemption entry');
    }
  }
  final VoucherRedemption redemption;
  final String entryId;
  final int balance;
}

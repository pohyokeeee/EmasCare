import '../models/backend_models.dart';
import '../models/wallet_models.dart';

abstract interface class WalletRepository {
  Stream<WalletRecord?> watchWallet(BackendProfile profile);
  Stream<List<WalletEntry>> watchWalletEntries(BackendProfile profile);
  Stream<List<RewardClaim>> watchRewardClaims(BackendProfile profile);
  Stream<List<DemoVoucher>> watchVouchers(BackendProfile profile);
  Stream<List<VoucherRedemption>> watchRedemptions(BackendProfile profile);
  Future<RedemptionResult> redeemDemoVoucher(Json fields, String key);
}

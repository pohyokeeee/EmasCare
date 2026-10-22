import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/backend_failure.dart';
import '../data/wallet_repository.dart';
import '../models/preview_models.dart';
import '../models/wallet_models.dart';
import 'session_controller.dart';
import 'session_workflow_controller.dart';

class WalletController extends ChangeNotifier {
  WalletController(this.session, this.repository) {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }
  final SessionController session;
  final WalletRepository repository;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Set<String> _ready = {};
  String? _scope;
  int _epoch = 0;
  bool _disposed = false, loading = false;
  BackendFailure? error;
  WalletRecord? wallet;
  List<WalletEntry> entries = [];
  List<RewardClaim> claims = [];
  List<DemoVoucher> vouchers = [];
  List<VoucherRedemption> redemptions = [];
  WorkflowAction? action;
  String? savedRedemptionId;
  String? get viewToken =>
      _scope == null || error != null ? null : '$_scope/$_epoch';
  String? get _currentScope {
    final p = session.connected ? session.profile : null;
    if (p == null || ![AppRole.elder, AppRole.helper].contains(p.role)) {
      return null;
    }
    return '${p.uid}/${p.role.name}/${p.townshipId}/${p.householdId}';
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _clear() {
    _epoch++;
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    _subscriptions.clear();
    _ready.clear();
    wallet = null;
    entries = [];
    claims = [];
    vouchers = [];
    redemptions = [];
    action = null;
    savedRedemptionId = null;
    loading = false;
    error = null;
  }

  void _sessionChanged() {
    final next = _currentScope;
    if (next == _scope) return;
    _scope = next;
    _bind();
  }

  void retry() => _bind();
  void _fail(Object failure) {
    _clear();
    error = BackendFailure.from(failure);
    _emit();
  }

  void _bind() {
    _clear();
    final p = session.profile;
    if (_scope == null || p == null) {
      _emit();
      return;
    }
    loading = true;
    final epoch = _epoch;
    bool valid() => !_disposed && epoch == _epoch && _scope == _currentScope;
    void listen<T>(String name, Stream<T> stream, void Function(T) apply) {
      _subscriptions.add(
        stream.listen(
          (value) {
            if (!valid()) return;
            try {
              apply(value);
              _ready.add(name);
              loading = _ready.length < 5;
              _emit();
            } catch (failure) {
              _fail(failure);
            }
          },
          onError: (Object failure) {
            if (valid()) _fail(failure);
          },
        ),
      );
    }

    listen('wallet', repository.watchWallet(p), (value) {
      if (value == null) {
        throw const BackendFailure('failed-precondition', 'WALLET_REQUIRED');
      }
      if (value.ownerUid != p.uid || value.townshipId != p.townshipId) {
        throw const BackendFailure('permission-denied', 'WALLET_ACCESS_DENIED');
      }
      wallet = value;
    });
    void owner(String uid, String township) {
      if (uid != p.uid || township != p.townshipId) {
        throw const BackendFailure('permission-denied', 'WALLET_ACCESS_DENIED');
      }
    }

    listen('entries', repository.watchWalletEntries(p), (value) {
      for (final row in value) {
        owner(row.ownerUid, row.townshipId);
      }
      entries = List.unmodifiable(value);
    });
    listen('claims', repository.watchRewardClaims(p), (value) {
      for (final row in value) {
        owner(row.beneficiaryUid, row.townshipId);
      }
      claims = List.unmodifiable(value);
    });
    listen('vouchers', repository.watchVouchers(p), (value) {
      for (final row in value) {
        owner(p.uid, row.townshipId);
      }
      vouchers = List.unmodifiable(value);
    });
    listen('redemptions', repository.watchRedemptions(p), (value) {
      for (final row in value) {
        owner(row.ownerUid, row.townshipId);
      }
      redemptions = List.unmodifiable(value);
    });
    _emit();
  }

  void discard() {
    if (action?.busy != true) action = null;
    _emit();
  }

  Future<bool> redeem(String voucherId) async {
    if (_disposed ||
        _scope == null ||
        _scope != _currentScope ||
        error != null ||
        loading ||
        wallet == null ||
        action?.busy == true) {
      return false;
    }
    final pending = action ??= WorkflowAction('redeem', {
      'voucherId': voucherId,
    });
    // Existing failed intent always retains its original voucher and key.
    pending.busy = true;
    pending.error = null;
    savedRedemptionId = null;
    final epoch = _epoch;
    _emit();
    try {
      final result = await repository.redeemDemoVoucher(
        pending.fields,
        pending.key,
      );
      if (_disposed || epoch != _epoch) return false;
      final p = session.profile!;
      if (result.redemption.ownerUid != p.uid ||
          result.redemption.townshipId != p.townshipId) {
        throw const BackendFailure('permission-denied', 'WALLET_ACCESS_DENIED');
      }
      if (result.redemption.voucherId != pending.fields['voucherId']) {
        throw const FormatException(
          'Redemption does not match the confirmed voucher',
        );
      }
      // Never copy a receipt's possibly stale balance over the wallet stream.
      savedRedemptionId = result.redemption.id;
      action = null;
      return true;
    } catch (failure) {
      if (_disposed || epoch != _epoch) return false;
      final parsed = BackendFailure.from(failure);
      if (['permission-denied', 'unauthenticated'].contains(parsed.code)) {
        _fail(parsed);
      } else {
        pending.error = parsed;
      }
      return false;
    } finally {
      pending.busy = false;
      _emit();
    }
  }

  Future<bool> retryRedemption() => action == null
      ? Future.value(false)
      : redeem(action!.fields['voucherId'] as String);
  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_sessionChanged);
    _clear();
    super.dispose();
  }
}

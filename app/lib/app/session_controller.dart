import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../data/backend_failure.dart';
import '../data/backend_repository.dart';
import '../models/backend_models.dart';
import '../models/preview_models.dart';

class PendingAction {
  PendingAction(this.key, this.fields, this.date);
  final String key, date;
  final Json fields;
  bool busy = false;
  BackendFailure? error;
}

class SessionController extends ChangeNotifier {
  SessionController(this.repository, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now {
    _date = malaysiaDate(this.clock());
    _auth = repository.authChanges().listen(_onAuth, onError: _authError);
    _dayTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final next = malaysiaDate(this.clock());
      if (next == _date) return;
      _date = next;
      if (profile != null) _bindDomain();
      _emit();
    });
  }
  final BackendRepository repository;
  final DateTime Function() clock;
  late final StreamSubscription<String?> _auth;
  late final Timer _dayTimer;
  StreamSubscription<BackendProfile?>? _profileSub;
  final List<StreamSubscription<dynamic>> _domain = [];
  StreamSubscription<List<DailyStatus>>? _familySub;
  int _epoch = 0, _profileVersion = 0, _domainEpoch = 0, _familyEpoch = 0;
  bool _disposed = false;
  String? _uid;
  late String _date;
  bool preview = false, loading = true, authBusy = false, dataLoading = false;
  BackendProfile? profile;
  BackendFailure? authError, dataError, familyError;
  ElderSettings? settings;
  List<CheckInRecord> checkins = [], exceptions = [];
  List<ElderAccess> elders = [];
  List<DailyStatus> statuses = [];
  String? selectedElderId;
  final Map<String, PendingAction> actions = {};
  String get today => malaysiaDate(clock());
  CheckInRecord? get todayCheckIn =>
      checkins.where((c) => c.localDate == today).firstOrNull;
  DailyStatus? get todayStatus =>
      statuses.where((s) => s.localDate == today).firstOrNull;
  ElderAccess? get selectedElder =>
      elders.where((e) => e.id == selectedElderId).firstOrNull;
  bool get connected => !preview && profile != null;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _clearDomain() {
    _domainEpoch++;
    for (final sub in _domain) {
      unawaited(sub.cancel());
    }
    _domain.clear();
    _clearFamily();
    settings = null;
    checkins = [];
    exceptions = [];
    elders = [];
    selectedElderId = null;
    dataError = null;
    dataLoading = false;
  }

  void _clearFamily() {
    _familyEpoch++;
    unawaited(_familySub?.cancel());
    _familySub = null;
    statuses = [];
    familyError = null;
  }

  void _onAuth(String? uid) {
    if (_disposed) return;
    final epoch = ++_epoch;
    _profileVersion++;
    unawaited(_profileSub?.cancel());
    _profileSub = null;
    _clearDomain();
    actions.clear();
    profile = null;
    _uid = uid;
    authError = null;
    loading = uid != null;
    if (uid != null && !preview) {
      _profileSub = repository
          .watchProfile(uid)
          .listen(
            (value) async {
              if (epoch != _epoch || _disposed) return;
              final version = ++_profileVersion;
              // Re-authorize before showing any data, including on profile changes.
              profile = null;
              _clearDomain();
              actions.clear();
              loading = true;
              _emit();
              try {
                if (value == null || value.uid != uid) {
                  throw const BackendFailure(
                    'permission-denied',
                    'PROFILE_REQUIRED',
                  );
                }
                final context = await repository.getBackendContext().timeout(
                  const Duration(seconds: 20),
                );
                if (epoch != _epoch ||
                    version != _profileVersion ||
                    _disposed) {
                  return;
                }
                if (!value.sameScope(context)) {
                  throw const BackendFailure(
                    'permission-denied',
                    'PROFILE_REQUIRED',
                  );
                }
                profile = value;
                authError = null;
                loading = false;
                _bindDomain();
              } catch (error) {
                if (epoch != _epoch ||
                    version != _profileVersion ||
                    _disposed) {
                  return;
                }
                profile = null;
                loading = false;
                authError = BackendFailure.from(error);
              }
              _emit();
            },
            onError: (Object error) {
              if (epoch != _epoch) return;
              _authError(error);
            },
          );
    }
    _emit();
  }

  void _authError(Object error) {
    _profileVersion++;
    profile = null;
    _clearDomain();
    loading = false;
    authError = BackendFailure.from(error);
    _emit();
  }

  Future<void> signIn(String email, String password) async {
    if (authBusy) return;
    authBusy = true;
    preview = false;
    authError = null;
    _emit();
    try {
      await repository
          .signIn(email.trim(), password)
          .timeout(const Duration(seconds: 20));
    } catch (error) {
      authError = BackendFailure.from(error);
    }
    authBusy = false;
    _emit();
  }

  Future<void> signOut({bool enterPreview = false}) async {
    if (authBusy) return;
    _epoch++;
    _profileVersion++;
    unawaited(_profileSub?.cancel());
    _profileSub = null;
    profile = null;
    _clearDomain();
    actions.clear();
    loading = false;
    authBusy = true;
    authError = null;
    _emit();
    try {
      await repository.signOut();
      preview = enterPreview;
    } catch (error) {
      authError = BackendFailure.from(error);
    }
    authBusy = false;
    _emit();
  }

  void leavePreview() {
    preview = false;
    _onAuth(_uid);
  }

  void retryProfile() {
    _onAuth(_uid);
  }

  void retryData() {
    if (profile != null) {
      _bindDomain();
      _emit();
    }
  }

  void _bindDomain() {
    _clearDomain();
    final p = profile;
    if (p == null) return;
    final epoch = _domainEpoch;
    bool valid() =>
        !_disposed && epoch == _domainEpoch && profile?.uid == p.uid;
    void failure(Object error) {
      if (!valid()) return;
      _clearDomain();
      dataError = BackendFailure.from(error);
      _emit();
    }

    dataLoading = p.role != AppRole.helper;
    switch (p.role) {
      case AppRole.elder:
        var settingsReady = false, checkinsReady = false;
        _domain.add(
          repository.watchSettings(p.uid).listen((value) {
            if (!valid()) return;
            settings = value;
            settingsReady = true;
            dataLoading = !(settingsReady && checkinsReady);
            _emit();
          }, onError: failure),
        );
        _domain.add(
          repository.watchCheckIns(p.uid).listen((value) {
            if (!valid()) return;
            checkins = value;
            checkinsReady = true;
            dataLoading = !(settingsReady && checkinsReady);
            _emit();
          }, onError: failure),
        );
      case AppRole.family:
        if (p.householdId == null) {
          dataLoading = false;
          return;
        }
        _domain.add(
          repository.watchHousehold(p).listen((value) {
            if (!valid()) return;
            elders = value.elders;
            if (!elders.any((e) => e.id == selectedElderId)) {
              _clearFamily();
              selectedElderId = elders.firstOrNull?.id;
            }
            if (selectedElder?.sharing != true) {
              _clearFamily();
            } else if (_familySub == null && familyError == null) {
              _bindFamily(p);
            }
            dataLoading = false;
            _emit();
          }, onError: failure),
        );
      case AppRole.coordinator:
        _domain.add(
          repository.watchExceptions(p.townshipId, today).listen((value) {
            if (!valid()) return;
            exceptions = value;
            dataLoading = false;
            _emit();
          }, onError: failure),
        );
      case AppRole.helper:
        break;
    }
  }

  void selectElder(String id) {
    if (profile == null || !elders.any((e) => e.id == id)) return;
    _clearFamily();
    selectedElderId = id;
    if (selectedElder?.sharing == true) _bindFamily(profile!);
    _emit();
  }

  void _bindFamily(BackendProfile p) {
    final elderId = selectedElderId!;
    final epoch = ++_familyEpoch;
    _familySub = repository
        .watchDailyStatuses(elderId, p.householdId!)
        .listen(
          (value) {
            if (_disposed ||
                epoch != _familyEpoch ||
                selectedElder?.sharing != true) {
              return;
            }
            statuses = value;
            _emit();
          },
          onError: (Object error) {
            if (epoch != _familyEpoch) return;
            _clearFamily();
            familyError = BackendFailure.from(error);
            _emit();
          },
        );
  }

  Future<void> _run(
    String name,
    Json fields,
    Future<Object?> Function(Json fields, String key) operation,
  ) async {
    if (!connected) return;
    var action = actions[name];
    if (action?.busy == true) return;
    action ??= actions[name] = PendingAction(
      'ui-${DateTime.now().microsecondsSinceEpoch}-${List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}',
      Map.unmodifiable(fields),
      today,
    );
    final current = action;
    current.busy = true;
    current.error = null;
    final epoch = _epoch;
    _emit();
    try {
      await operation(current.fields, current.key);
      if (epoch == _epoch && !_disposed && identical(actions[name], current)) {
        actions.remove(name);
      }
      // Streams remain authoritative: replayed responses may predate a later save.
    } catch (error) {
      if (epoch == _epoch && !_disposed && identical(actions[name], current)) {
        current.error = BackendFailure.from(error);
      }
    }
    current.busy = false;
    _emit();
  }

  Future<void> saveSettings(Json fields) => _run(
    'settings',
    fields,
    (payload, key) => repository.saveElderSettings(payload, key),
  );
  Future<void> checkIn() =>
      _run('checkin', {}, (_, key) => repository.submitCheckIn(key));
  Future<void> phoneResponse(String elderId) => _run(
    'phone:$elderId',
    {'elderId': elderId},
    (payload, key) =>
        repository.recordPhoneResponse(payload['elderId'] as String, key),
  );
  void cancelAction(String name) {
    if (actions[name]?.busy != true) actions.remove(name);
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _profileVersion++;
    _dayTimer.cancel();
    unawaited(_auth.cancel());
    unawaited(_profileSub?.cancel());
    _clearDomain();
    super.dispose();
  }
}

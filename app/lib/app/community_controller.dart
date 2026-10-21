import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/backend_failure.dart';
import '../data/community_repository.dart';
import '../models/backend_models.dart';
import '../models/community_models.dart';
import '../models/preview_models.dart';
import 'session_controller.dart';

class CommunityController extends ChangeNotifier {
  CommunityController(this.session, this.repository) {
    session.addListener(_sessionChanged);
    _sessionChanged();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_disposed) notifyListeners();
    });
  }
  final SessionController session;
  final CommunityRepository repository;
  BackendProfile? _scope;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  late final Timer _timer;
  Timer? _noticeExpiry;
  int _epoch = 0;
  bool _disposed = false;
  List<ActivityRecord> activities = [];
  List<PlaceRecord> places = [];
  List<PairingRecord> pairings = [];
  HelperProfileRecord? helper;
  bool catalogLoading = false, pairingLoading = false, helperLoading = false;
  BackendFailure? catalogError, pairingError, helperError;
  DateTime get now => session.clock().toUtc();
  PlaceRecord? place(String id) => places.where((p) => p.id == id).firstOrNull;
  void _clear() {
    _epoch++;
    _noticeExpiry?.cancel();
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions.clear();
    activities = [];
    places = [];
    pairings = [];
    helper = null;
    catalogLoading = false;
    pairingLoading = false;
    helperLoading = false;
    catalogError = null;
    pairingError = null;
    helperError = null;
  }

  void _scheduleNoticeExpiry() {
    _noticeExpiry?.cancel();
    final expiries =
        places
            .map((p) => p.notice?.expiresAt)
            .whereType<DateTime>()
            .where((time) => time.isAfter(now))
            .toList()
          ..sort();
    if (expiries.isEmpty) return;
    final epoch = _epoch;
    _noticeExpiry = Timer(expiries.first.difference(now), () {
      if (_disposed || epoch != _epoch) return;
      notifyListeners();
      _scheduleNoticeExpiry();
    });
  }

  void _sessionChanged() {
    final profile = session.connected ? session.profile : null;
    if (profile == null && _scope == null) return;
    if (profile != null && _scope?.sameScope(profile) == true) return;
    _scope = profile;
    _bind();
  }

  void retry() => _bind();
  void _bind() {
    _clear();
    final p = _scope;
    if (p == null) {
      notifyListeners();
      return;
    }
    final epoch = _epoch;
    bool valid() => !_disposed && epoch == _epoch;
    var activitiesReady = false, placesReady = false;
    catalogLoading = true;
    void catalogFailure(Object error) {
      if (!valid()) return;
      // Invalidate every pending callback before rendering cleared private data.
      _clear();
      catalogError = BackendFailure.from(error);
      notifyListeners();
    }

    _subscriptions.add(
      repository.watchActivities(p.townshipId).listen((value) {
        if (!valid()) return;
        activities = value;
        activitiesReady = true;
        catalogLoading = !(activitiesReady && placesReady);
        notifyListeners();
      }, onError: catalogFailure),
    );
    _subscriptions.add(
      repository.watchPlaces(p.townshipId).listen((value) {
        if (!valid()) return;
        places = value;
        _scheduleNoticeExpiry();
        placesReady = true;
        catalogLoading = !(activitiesReady && placesReady);
        notifyListeners();
      }, onError: catalogFailure),
    );
    if (p.role != AppRole.family) {
      pairingLoading = true;
      _subscriptions.add(
        repository.watchPairings(p).listen((value) {
          if (!valid()) return;
          pairings = value;
          pairingLoading = false;
          notifyListeners();
        }, onError: catalogFailure),
      );
    }
    if (p.role == AppRole.helper) {
      helperLoading = true;
      _subscriptions.add(
        repository.watchHelperProfile(p.uid).listen((value) {
          if (!valid()) return;
          helper = value;
          helperLoading = false;
          notifyListeners();
        }, onError: catalogFailure),
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer.cancel();
    session.removeListener(_sessionChanged);
    _clear();
    super.dispose();
  }
}

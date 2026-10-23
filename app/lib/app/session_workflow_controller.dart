import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../data/backend_failure.dart';
import '../data/session_repository.dart';
import '../data/availability_repository.dart';
import '../models/backend_models.dart';
import '../models/preview_models.dart';
import '../models/session_models.dart';
import 'session_controller.dart';

Object? _freeze(Object? value) => value is Map
    ? Map<String, dynamic>.unmodifiable(
        value.map((k, v) => MapEntry(k as String, _freeze(v))),
      )
    : value is List
    ? List.unmodifiable(value.map(_freeze))
    : value;

class WorkflowAction {
  WorkflowAction(this.kind, Json fields)
    : fields = _freeze(fields) as Json,
      key =
          'session-${DateTime.now().microsecondsSinceEpoch}-${List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  final String kind, key;
  final Json fields;
  bool busy = false;
  BackendFailure? error;
}

class SessionWorkflowController extends ChangeNotifier {
  SessionWorkflowController(this.session, this.repository) {
    session.addListener(_sessionChanged);
    _sessionChanged();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) => _emit());
  }
  final SessionController session;
  final SessionRepository repository;
  StreamSubscription<List<SessionRequest>>? _subscription;
  late final Timer _clock;
  Timer? _boundary;
  String? _scope;
  bool _disposed = false;
  int _epoch = 0, _intent = 0;
  RequestState queue = RequestState.requested;
  List<SessionRequest> requests = [];
  final Map<String, WorkflowAction> actions = {};
  BackendFailure? error;
  bool loading = false;
  DateTime get now => session.clock().toUtc();
  String nextIntent() => 'intent-${++_intent}';
  SessionRequest? request(String id) =>
      requests.where((r) => r.id == id).firstOrNull;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  String? get _currentScope {
    final p = session.connected ? session.profile : null;
    if (p == null) return null;
    if (p.role == AppRole.family &&
        (session.selectedElder?.booking != true || session.dataError != null)) {
      return null;
    }
    return '${p.uid}/${p.role}/${p.townshipId}/${p.householdId}/${p.role == AppRole.family ? session.selectedElderId : "self"}/${p.role == AppRole.coordinator ? queue.wire : "all"}';
  }

  void _clear({bool pending = true}) {
    _epoch++;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _boundary?.cancel();
    requests = [];
    loading = false;
    error = null;
    if (pending) actions.clear();
  }

  void _sessionChanged() {
    final scope = _currentScope;
    if (scope == _scope) return;
    _scope = scope;
    _bind();
  }

  void retry() => _bind();
  void selectQueue(RequestState state) {
    if (queue == state) return;
    queue = state;
    _sessionChanged();
  }

  void _bind() {
    _clear();
    final p = session.profile;
    if (_scope == null || p == null) {
      _emit();
      return;
    }
    final epoch = _epoch;
    loading = true;
    _subscription = repository
        .watchRequests(p, elderId: session.selectedElderId, queue: queue)
        .listen(
          (value) {
            if (_disposed || epoch != _epoch) return;
            requests = value;
            loading = false;
            _scheduleBoundary();
            _emit();
          },
          onError: (Object failure) {
            if (epoch != _epoch || _disposed) return;
            _clear();
            error = BackendFailure.from(failure);
            _emit();
          },
        );
    _emit();
  }

  void _scheduleBoundary() {
    _boundary?.cancel();
    final dates =
        requests
            .expand((r) => [r.startsAt, r.endsAt])
            .where((t) => t.isAfter(now))
            .toList()
          ..sort();
    if (dates.isEmpty) return;
    _boundary = Timer(dates.first.difference(now), () {
      if (!_disposed) {
        _emit();
        _scheduleBoundary();
      }
    });
  }

  bool busy(String name) => actions[name]?.busy == true;
  void discard(String name) {
    if (!busy(name)) actions.remove(name);
    _emit();
  }

  Future<bool> run(String name, String kind, Json fields) async {
    final availabilityAction = kind == 'companionAvailability';
    if (_disposed ||
        (!availabilityAction && (_scope == null || _currentScope != _scope)) ||
        (availabilityAction && (!session.connected ||
            ![AppRole.family, AppRole.helper].contains(session.profile?.role))) ||
        error != null ||
        busy(name)) {
      return false;
    }
    final action = actions.putIfAbsent(
      name,
      () => WorkflowAction(kind, fields),
    );
    action.busy = true;
    action.error = null;
    final epoch = _epoch;
    _emit();
    try {
      switch (action.kind) {
        case 'create':
          await repository.createRequest(action.fields, action.key);
        case 'assign':
          await repository.assignRequest(action.fields, action.key);
        case 'transition':
          await repository.transitionRequest(action.fields, action.key);
        case 'availability':
          await repository.setHelperAvailability(action.fields, action.key);
        case 'companionAvailability':
          final availability = repository is AvailabilityRepository
              ? repository as AvailabilityRepository
              : null;
          if (availability == null) {
            throw const BackendFailure('failed-precondition', 'AVAILABILITY_NOT_CONNECTED');
          }
          await availability.setCompanionAvailability(action.fields, action.key);
        default:
          throw const BackendFailure('invalid-argument');
      }
      if (_disposed || epoch != _epoch) return false;
      actions.remove(name);
      return true;
    } catch (failure) {
      if (_disposed || epoch != _epoch) return false;
      final parsed = BackendFailure.from(failure);
      if (parsed.code == 'permission-denied' ||
          parsed.code == 'unauthenticated') {
        _clear();
        error = parsed;
      } else {
        action.error = parsed;
      }
      return false;
    } finally {
      action.busy = false;
      _emit();
    }
  }

  Future<bool> retryAction(String name) {
    final a = actions[name];
    return a == null ? Future.value(false) : run(name, a.kind, a.fields);
  }

  Future<bool> transition(String id, String action) =>
      run('request:$id', 'transition', {'requestId': id, 'action': action});
  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_sessionChanged);
    _clock.cancel();
    _clear();
    super.dispose();
  }
}

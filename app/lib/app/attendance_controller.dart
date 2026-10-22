import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/attendance_repository.dart';
import '../data/backend_failure.dart';
import '../models/attendance_models.dart';
import '../models/backend_models.dart';
import '../models/preview_models.dart';
import 'session_controller.dart';
import 'session_workflow_controller.dart';

class AttendanceController extends ChangeNotifier {
  AttendanceController(this.session, this.repository) {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }
  final SessionController session;
  final AttendanceRepository repository;
  StreamSubscription<List<ActivityAttendance>>? _subscription;
  String? _scope;
  int _epoch = 0;
  bool _disposed = false, loading = false;
  BackendFailure? error;
  List<ActivityAttendance> records = [];
  final Map<String, WorkflowAction> actions = {};
  String? get viewToken =>
      _scope == null || error != null ? null : '$_scope/$_epoch';
  String? get _currentScope {
    final p = session.connected ? session.profile : null;
    if (p == null || p.role == AppRole.helper) return null;
    if (p.role == AppRole.family &&
        (session.selectedElder?.sharing != true || session.dataError != null)) {
      return null;
    }
    return '${p.uid}/${p.role.name}/${p.townshipId}/${p.householdId}/${p.role == AppRole.family ? session.selectedElderId : "self"}';
  }

  ActivityAttendance? forActivity(String id) =>
      records.where((r) => r.activityId == id).firstOrNull;
  ActivityAttendance? record(String id) =>
      records.where((r) => r.id == id).firstOrNull;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _clear() {
    _epoch++;
    unawaited(_subscription?.cancel());
    _subscription = null;
    records = [];
    actions.clear();
    loading = false;
    error = null;
  }

  void _sessionChanged() {
    final scope = _currentScope;
    if (scope == _scope) return;
    _scope = scope;
    _bind();
  }

  void retry() => _bind();
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
        .watchAttendance(p, elderId: session.selectedElderId)
        .listen(
          (value) {
            if (_disposed || epoch != _epoch) return;
            records = List.unmodifiable(value);
            loading = false;
            _emit();
          },
          onError: (Object failure) {
            if (_disposed || epoch != _epoch) return;
            _clear();
            error = BackendFailure.from(failure);
            _emit();
          },
        );
    _emit();
  }

  bool busy(String name) => actions[name]?.busy == true;
  void discard(String name) {
    if (!busy(name)) actions.remove(name);
    _emit();
  }

  Future<bool> run(String name, String kind, Json fields) async {
    if (_disposed ||
        _scope == null ||
        _scope != _currentScope ||
        error != null ||
        busy(name)) {
      return false;
    }
    final role = session.profile!.role;
    if ((kind == 'submit' && role != AppRole.elder) ||
        (kind == 'review' && role != AppRole.coordinator) ||
        !['submit', 'review'].contains(kind)) {
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
      if (action.kind == 'submit') {
        await repository.submitActivityAttendance(action.fields, action.key);
      } else {
        await repository.reviewActivityAttendance(action.fields, action.key);
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

  Future<bool> submit(String activityId) =>
      run('submit:$activityId', 'submit', {'activityId': activityId});
  Future<bool> review(String id, Json fields) =>
      run('review:$id', 'review', {'attendanceId': id, ...fields});
  Future<bool> retryAction(String name) {
    final action = actions[name];
    return action == null
        ? Future.value(false)
        : run(name, action.kind, action.fields);
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_sessionChanged);
    _clear();
    super.dispose();
  }
}

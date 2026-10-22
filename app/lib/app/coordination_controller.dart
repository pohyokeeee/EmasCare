import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/backend_failure.dart';
import '../data/coordination_repository.dart';
import '../models/backend_models.dart';
import '../models/coordination_models.dart';
import '../models/preview_models.dart';
import 'session_controller.dart';
import 'session_workflow_controller.dart';

class CoordinationController extends ChangeNotifier {
  CoordinationController(this.session, this.repository, this.sessions) {
    session.addListener(_sync);
    sessions?.addListener(_sync);
    _sync();
  }
  final SessionController session;
  final CoordinationRepository repository;
  final SessionWorkflowController? sessions;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<StreamSubscription<dynamic>> _requestSubscriptions = [];
  final Map<String, List<ReportRecord>> _reportGroups = {};
  final Map<String, List<NoticeRecord>> _noticeGroups = {};
  final Map<String, WorkflowAction> actions = {};
  final Map<String, BackendFailure> errors = {};
  final Set<String> loading = {};
  final Map<String, ProgressRecord> progress = {};
  final Map<String, int> _readVersions = {};
  Json? availability, summary, dueResult;
  VoiceBookingResult? voice;
  List<Json> cheers = [], blocks = [], elderProfiles = [];
  String periodType = 'week';
  String? selectedCoordinatorElder;
  String? _scope, _requestsSignature;
  int _epoch = 0, _streamEpoch = 0, _intent = 0, _voiceVersion = 0;
  bool _disposed = false, voiceBusy = false;
  String? voiceErrorMessage;
  String nextIntent() => 'coord-${++_intent}';
  String? get viewToken => _scope == null ? null : '$_scope/$_epoch';
  List<ReportRecord> get reports =>
      _reportGroups.values.expand((r) => r).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  List<NoticeRecord> get notices =>
      _noticeGroups.values.expand((r) => r).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  String? get elderId => switch (session.profile?.role) {
    AppRole.elder => session.profile?.uid,
    AppRole.family => session.selectedElderId,
    AppRole.coordinator => selectedCoordinatorElder,
    _ => null,
  };
  bool get mayShare =>
      session.profile?.role != AppRole.family ||
      session.selectedElder?.sharing == true;
  bool get mayBook =>
      session.profile?.role == AppRole.elder ||
      session.profile?.role == AppRole.family &&
          session.selectedElder?.booking == true;
  String? get _currentScope {
    final p = session.connected ? session.profile : null;
    if (p == null) return null;
    return '${p.uid}/${p.role.name}/${p.townshipId}/${p.householdId}/${p.role == AppRole.family ? '${session.selectedElderId}/${session.selectedElder?.sharing}/${session.selectedElder?.booking}/${session.dataError?.code}' : 'self'}';
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _clear() {
    _epoch++;
    _streamEpoch++;
    _voiceVersion++;
    for (final sub in [..._subscriptions, ..._requestSubscriptions]) {
      unawaited(sub.cancel());
    }
    _subscriptions.clear();
    _requestSubscriptions.clear();
    _reportGroups.clear();
    _noticeGroups.clear();
    _readVersions.clear();
    progress.clear();
    actions.clear();
    errors.clear();
    loading.clear();
    availability = summary = dueResult = null;
    voice = null;
    voiceBusy = false;
    voiceErrorMessage = null;
    cheers = [];
    blocks = [];
    elderProfiles = [];
    selectedCoordinatorElder = null;
    _requestsSignature = null;
  }

  void _sync() {
    if (_disposed) return;
    final scope = _currentScope;
    if (scope != _scope) {
      _scope = scope;
      _bind();
      return;
    }
    if (_scope == null) return;
    final signature = (sessions?.requests ?? [])
        .map((r) => '${r.id}/${r.updatedAt.microsecondsSinceEpoch}')
        .join('|');
    if (signature != _requestsSignature) {
      _bindRequests();
      unawaited(refresh());
    }
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
    void listen<T>(String name, Stream<T> stream, void Function(T) apply) {
      _subscriptions.add(
        stream.listen(
          (value) {
            if (_disposed || epoch != _epoch) return;
            try {
              apply(value);
              errors.remove(name);
              _emit();
            } catch (e) {
              errors[name] = BackendFailure.from(e);
              _emit();
            }
          },
          onError: (Object e) {
            if (_disposed || epoch != _epoch) return;
            errors[name] = BackendFailure.from(e);
            if (name == 'cheers') cheers = [];
            if (name == 'blocks') blocks = [];
            if (name == 'elders') elderProfiles = [];
            _emit();
          },
          cancelOnError: true,
        ),
      );
    }

    if (p.role == AppRole.coordinator) {
      listen('elders', repository.watchTownshipElders(p), (rows) {
        elderProfiles = rows;
        if (!rows.any((e) => e['id'] == selectedCoordinatorElder)) {
          selectedCoordinatorElder = rows.firstOrNull?['id'] as String?;
          unawaited(refresh());
        }
        _bindRequests();
      });
    }
    if ([AppRole.elder, AppRole.coordinator].contains(p.role)) {
      listen(
        'blocks',
        repository.watchHelperBlocks(p),
        (rows) => blocks = rows,
      );
    }
    _bindRequests();
    unawaited(refresh());
    _emit();
  }

  void _bindRequests() {
    final p = session.profile;
    if (p == null || _scope == null) return;
    _streamEpoch++;
    final streamEpoch = _streamEpoch, epoch = _epoch;
    for (final sub in _requestSubscriptions) {
      unawaited(sub.cancel());
    }
    _requestSubscriptions.clear();
    _reportGroups.clear();
    _noticeGroups.clear();
    cheers = [];
    _requestsSignature = (sessions?.requests ?? [])
        .map((r) => '${r.id}/${r.updatedAt.microsecondsSinceEpoch}')
        .join('|');
    bool valid() =>
        !_disposed && epoch == _epoch && streamEpoch == _streamEpoch;
    void watch(
      String key,
      Stream<List<Json>> stream,
      void Function(List<Json>) apply,
      void Function() clear,
    ) {
      errors.remove(key);
      _requestSubscriptions.add(
        stream.listen(
          (rows) {
            if (!valid()) return;
            try {
              apply(rows);
              errors.remove(key);
              _emit();
            } catch (e) {
              clear();
              errors[key] = BackendFailure.from(e);
              _emit();
            }
          },
          onError: (Object e) {
            if (valid()) {
              clear();
              errors[key] = BackendFailure.from(e);
              _emit();
            }
          },
          cancelOnError: true,
        ),
      );
    }

    final requests = sessions?.requests ?? [];
    final reportQueries = <String?>{
      null,
      if (p.role != AppRole.coordinator) ...requests.map((r) => r.id),
    };
    for (final id in reportQueries) {
      final key = 'reports:${id ?? 'unlinked'}';
      final request = requests.where((r) => r.id == id).firstOrNull;
      watch(
        key,
        repository.watchCoordinationReports(
          p,
          requestId: id,
          elderId: request?.elderId,
          householdId: request?.householdId,
        ),
        (rows) {
          final records = rows.map(ReportRecord.fromJson).toList();
          if (records.any(
            (r) =>
                r.townshipId != p.townshipId ||
                p.role != AppRole.coordinator && r.createdBy != p.uid,
          )) {
            throw const BackendFailure(
              'permission-denied',
              'REPORT_ACCESS_DENIED',
            );
          }
          _reportGroups[key] = records;
        },
        () => _reportGroups.remove(key),
      );
    }
    final elders = <String>{
      if (p.role == AppRole.elder) p.uid,
      if (p.role == AppRole.family && elderId != null) elderId!,
      if (p.role == AppRole.helper) ...requests.map((r) => r.elderId),
      if (p.role == AppRole.coordinator)
        ...elderProfiles.map((e) => e['id'] as String),
    };
    final scopes = p.role == AppRole.family
        ? <String>{
            if (session.selectedElder?.sharing == true) 'daily_sharing',
            if (session.selectedElder?.booking == true) 'family_booking',
          }
        : {'none'};
    for (final e in elders) {
      for (final consent in scopes) {
        final key = 'notices:$e:$consent';
        watch(key, repository.watchNotices(p, e, consent), (rows) {
          final records = rows.map(NoticeRecord.fromJson).toList();
          if (records.any(
            (n) =>
                n.recipientUid != p.uid ||
                n.elderId != e ||
                n.consentScope != consent,
          )) {
            throw const BackendFailure(
              'permission-denied',
              'NOTIFICATION_ACCESS_DENIED',
            );
          }
          _noticeGroups[key] = records;
        }, () => _noticeGroups.remove(key));
      }
    }
    if (elderId != null && mayShare) {
      final e = elderId!;
      watch('cheers', repository.watchCheers(e), (rows) {
        if (rows.any((r) => r['elderId'] != e)) {
          throw const BackendFailure('permission-denied');
        }
        cheers = rows;
      }, () => cheers = []);
    }
    _emit();
  }

  Future<void> _read(
    String key,
    String name,
    Json fields,
    void Function(Json) apply,
  ) async {
    final epoch = _epoch, version = (_readVersions[key] ?? 0) + 1;
    _readVersions[key] = version;
    loading.add(key);
    errors.remove(key);
    _emit();
    try {
      final result = await repository.coordinationCall(name, fields);
      if (_disposed || epoch != _epoch || _readVersions[key] != version) return;
      apply(result);
    } catch (e) {
      if (_disposed || epoch != _epoch || _readVersions[key] != version) return;
      errors[key] = BackendFailure.from(e);
      if (key.startsWith('progress:')) progress.remove(key.substring(9));
      if (key == 'availability') availability = null;
      if (key == 'summary') summary = null;
    } finally {
      if (!_disposed && epoch == _epoch && _readVersions[key] == version) {
        loading.remove(key);
        _emit();
      }
    }
  }

  Future<void> refresh() async {
    final p = session.profile;
    if (_scope == null || p == null || _disposed) return;
    final jobs = <Future<void>>[];
    void addProgress(String scope, String entity) {
      jobs.add(
        _read(
          'progress:$scope',
          'getProgress',
          {
            'scope': scope,
            'entityId': entity,
            'periodType': periodType,
            'periodKey': null,
          },
          (r) {
            final value = ProgressRecord.fromJson(jsonObject(r['progress']));
            if (value.scope != scope ||
                value.entityId != entity ||
                value.periodType != periodType) {
              throw const FormatException('Progress scope');
            }
            progress[scope] = value;
          },
        ),
      );
    }

    if (elderId != null && mayShare) addProgress('elder', elderId!);
    if (p.role == AppRole.helper) addProgress('helper', p.uid);
    if (p.householdId != null) addProgress('household', p.householdId!);
    addProgress('township', p.townshipId);
    jobs.add(
      _read('availability', 'getAvailabilitySummary', {}, (r) {
        final value = jsonObject(r['availabilitySummary']);
        if (value['townshipId'] != p.townshipId || value['isDemo'] != true) {
          throw const FormatException('Availability scope');
        }
        utcTimestamp(value['updatedAt'])!;
        for (final raw in value['cells'] as List) {
          final cell = jsonObject(raw);
          if (cell['weekday'] is! int ||
              cell['weekday'] < 1 ||
              cell['weekday'] > 7 ||
              cell['startMinute'] is! int ||
              cell['endMinute'] is! int ||
              cell['startMinute'] < 0 ||
              cell['endMinute'] > 1440 ||
              cell['startMinute'] >= cell['endMinute']) {
            throw const FormatException('Invalid availability cell');
          }
          if (cell['suppressed'] == true) {
            if (cell['helperCount'] != null || cell['requestCount'] != null) {
              throw const FormatException('Unsuppressed private count');
            }
          } else {
            countValue(cell['helperCount']);
            countValue(cell['requestCount']);
          }
        }
        availability = value;
      }),
    );
    if (p.role == AppRole.coordinator) {
      jobs.add(
        _read('summary', 'getCoordinatorSummary', {}, (r) {
          final value = jsonObject(r['summary']);
          if (value['townshipId'] != p.townshipId) {
            throw const FormatException('Summary scope');
          }
          utcTimestamp(value['updatedAt'])!;
          for (final name in [
            'checkins',
            'requests',
            'attendance',
            'reports',
            'placeWarnings',
          ]) {
            for (final count in jsonObject(value[name]).values) {
              countValue(count);
            }
          }
          summary = value;
        }),
      );
    }
    await Future.wait(jobs);
  }

  void selectPeriod(String value) {
    if (!['week', 'month'].contains(value) || value == periodType) return;
    periodType = value;
    progress.clear();
    unawaited(refresh());
    _emit();
  }

  void selectElder(String id) {
    if (!elderProfiles.any((e) => e['id'] == id)) return;
    selectedCoordinatorElder = id;
    progress.remove('elder');
    _bindRequests();
    unawaited(refresh());
    _emit();
  }

  Future<bool> run(String actionId, String name, Json fields) async {
    if (_disposed ||
        _scope == null ||
        _scope != _currentScope ||
        actions[actionId]?.busy == true) {
      return false;
    }
    final pending = actions[actionId] ??= WorkflowAction(name, fields);
    final epoch = _epoch;
    pending.busy = true;
    pending.error = null;
    _emit();
    try {
      final result = await repository.coordinationCall(
        pending.kind,
        pending.fields,
        idempotencyKey: pending.key,
      );
      if (_disposed || epoch != _epoch) return false;
      if (pending.kind == 'processDemoDueItems') {
        dueResult = result;
        session.retryData();
      }
      actions.remove(actionId);
      unawaited(refresh());
      return true;
    } catch (e) {
      if (_disposed || epoch != _epoch) return false;
      pending.error = BackendFailure.from(e);
      if ([
        'permission-denied',
        'unauthenticated',
      ].contains(pending.error!.code)) {
        final failure = pending.error!;
        _clear();
        errors['access'] = failure;
      }
      return false;
    } finally {
      pending.busy = false;
      _emit();
    }
  }

  Future<bool> retryAction(String id) {
    final a = actions[id];
    return a == null ? Future.value(false) : run(id, a.kind, a.fields);
  }

  void discard(String id) {
    if (actions[id]?.busy != true) actions.remove(id);
    _emit();
  }

  Future<void> parseVoice(Json input, String locale) async {
    if (voiceBusy || !mayBook || elderId == null || _scope == null) return;
    final epoch = _epoch, version = ++_voiceVersion;
    voiceBusy = true;
    voice = null;
    errors.remove('voice');
    _emit();
    try {
      final r = VoiceBookingResult.fromJson(
        await repository.coordinationCall('parseVoiceBooking', {
          'elderId': elderId,
          'locale': locale,
          'input': input,
        }),
      );
      if (_disposed || epoch != _epoch || version != _voiceVersion) return;
      if (r.draft?['elderId'] != null && r.draft!['elderId'] != elderId) {
        throw const FormatException('Voice booking scope');
      }
      voice = r;
    } catch (e) {
      if (!_disposed && epoch == _epoch && version == _voiceVersion) {
        errors['voice'] = BackendFailure.from(e);
      }
    } finally {
      if (!_disposed && epoch == _epoch && version == _voiceVersion) {
        voiceBusy = false;
        _emit();
      }
    }
  }

  void clearVoice() {
    _voiceVersion++;
    voice = null;
    voiceBusy = false;
    errors.remove('voice');
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_sync);
    sessions?.removeListener(_sync);
    _clear();
    super.dispose();
  }
}

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
import 'package:emas_care/app/coordination_controller.dart';
import 'package:emas_care/data/coordination_repository.dart';
import 'package:emas_care/data/backend_failure.dart';
import 'package:emas_care/data/emas_repository.dart';
import 'package:emas_care/data/firebase_backend_repository.dart';
import 'package:emas_care/models/backend_models.dart';
import 'package:emas_care/models/coordination_models.dart';
import 'package:emas_care/models/preview_models.dart';
import 'package:emas_care/features/coordination/coordination_view.dart';
import 'package:emas_care/shared/design_system.dart';
import 'backend_test.dart' as auth;
import 'stage4_test.dart' as stage4;
import 'stage5_test.dart' as stage5;

final fixture = jsonObject(
  jsonDecode(
    File('../docs/fixtures/stage6_coordination.json').readAsStringSync(),
  ),
);
final steps = (fixture['steps'] as List).map(jsonObject).toList();
Json result(String name) => FirebaseBackendRepository.unwrapEnvelope(
  steps.firstWhere((s) => s['functionName'] == name)['output'],
);

class CoordinationFake extends stage5.WalletFake
    implements CoordinationRepository {
  final coordCalls = <(String, Json, String?)>[];
  final scopes = <String>[];
  final events = <String, StreamController<List<Json>>>{};
  final reportsData = <Json>[],
      noticesData = <Json>[],
      cheersData = <Json>[],
      blocksData = <Json>[];
  int cancelled = 0;
  bool voiceUnavailable = false;
  Future<Json> Function(String, Json, String?)? command;
  Stream<List<Json>> stream(String key) {
    scopes.add(key);
    return (events[key] ??= StreamController<List<Json>>.broadcast(
      sync: true,
      onCancel: () => cancelled++,
    )).stream;
  }

  @override
  Stream<List<Json>> watchCoordinationReports(
    BackendProfile p, {
    String? requestId,
    String? elderId,
    String? householdId,
  }) => stream('reports/${p.uid}/${requestId ?? 'unlinked'}');
  @override
  Stream<List<Json>> watchNotices(
    BackendProfile p,
    String elder,
    String consent,
  ) => stream('notices/${p.uid}/$elder/$consent');
  @override
  Stream<List<Json>> watchCheers(String elder) => stream('cheers/$elder');
  @override
  Stream<List<Json>> watchTownshipElders(BackendProfile p) =>
      stream('elders/${p.townshipId}');
  @override
  Stream<List<Json>> watchHelperBlocks(BackendProfile p) =>
      stream('blocks/${p.uid}');
  void emitCoord() {
    for (final e in events.entries.toList()) {
      if (e.key.startsWith('reports/')) e.value.add(reportsData);
      if (e.key.startsWith('notices/')) {
        final s = e.key.split('/');
        e.value.add(
          noticesData
              .where(
                (n) =>
                    n['recipientUid'] == s[1] &&
                    n['elderId'] == s[2] &&
                    n['consentScope'] == s[3],
              )
              .toList(),
        );
      }
      if (e.key.startsWith('cheers/')) e.value.add(cheersData);
      if (e.key.startsWith('blocks/')) e.value.add(blocksData);
      if (e.key.startsWith('elders/')) {
        e.value.add([
          {'id': 'elder_demo', 'displayName': 'Demo Elder'},
        ]);
      }
    }
  }

  @override
  Future<Json> coordinationCall(
    String name,
    Json fields, {
    String? idempotencyKey,
  }) async {
    coordCalls.add((name, fields, idempotencyKey));
    if (command != null) return command!(name, fields, idempotencyKey);
    if (name == 'getProgress') {
      final base = jsonObject(result('getProgress')['progress']);
      return {
        'progress': {
          ...base,
          'scope': fields['scope'],
          'entityId': fields['entityId'],
          'periodType': fields['periodType'],
        },
      };
    }
    if (name == 'parseVoiceBooking' && voiceUnavailable) {
      throw const BackendFailure(
        'failed-precondition',
        'VOICE_SERVICE_UNAVAILABLE',
      );
    }
    if (name == 'submitReport') {
      final r = {
        ...jsonObject(result(name)['report']),
        ...fields,
        'createdBy': current.uid,
      };
      reportsData.add(r);
      emitCoord();
      return {'report': r};
    }
    if (name == 'sendFamilyCheer') {
      cheersData.add(jsonObject(result(name)['cheer']));
      emitCoord();
    }
    return result(name);
  }

  @override
  Future<void> close() async {
    await super.close();
    for (final e in events.values) {
      await e.close();
    }
  }
}

Future<void> flush() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> sign(CoordinationFake f, SessionController s, AppRole role) async {
  await stage4.signAs(f, s, role);
  f.emitCommunity();
  f.emitWallet();
  f.emitCoord();
  await flush();
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
    'published Stage 6 envelopes parse ISO and Firestore times without changing pending/suppressed fields',
    () {
      Object? timestamps(Object? v) => v is Map
          ? v.map((k, x) => MapEntry(k, timestamps(x)))
          : v is List
          ? v.map(timestamps).toList()
          : v is String && RegExp(r'^2026-.*T.*Z$').hasMatch(v)
          ? Timestamp.fromDate(DateTime.parse(v))
          : v;
      for (final s in steps) {
        final data = FirebaseBackendRepository.unwrapEnvelope(s['output']);
        final converted = jsonObject(timestamps(data));
        if (data['progress'] != null) {
          final a = ProgressRecord.fromJson(jsonObject(data['progress'])),
              b = ProgressRecord.fromJson(jsonObject(converted['progress']));
          expect(a.updatedAt, b.updatedAt);
          expect(a.counts, b.counts);
        }
        if (data['report'] != null) {
          expect(
            ReportRecord.fromJson(jsonObject(data['report'])).createdAt,
            ReportRecord.fromJson(jsonObject(converted['report'])).createdAt,
          );
        }
        if (s['functionName'] == 'parseVoiceBooking') {
          expect(VoiceBookingResult.fromJson(data).canConfirm, true);
        }
      }
      final progress = jsonObject(result('getProgress')['progress']);
      expect(
        () => ProgressRecord.fromJson({
          ...progress,
          'targets': {
            'outings': 0,
            'helpingSessions': null,
            'weekendGiveBack': null,
          },
        }),
        throwsFormatException,
      );
      expect(
        () => VoiceBookingResult.fromJson({
          ...result('parseVoiceBooking'),
          'missingFields': ['placeId'],
        }),
        throwsFormatException,
      );
      final cells =
          jsonObject(
                result('getAvailabilitySummary')['availabilitySummary'],
              )['cells']
              as List;
      expect(cells.last['helperCount'], isNull);
      expect(cells.last['suppressed'], true);
    },
  );

  test(
    'confirmed mutation freezes nested fields, blocks duplicate taps and retains its key on retry',
    () async {
      final f = CoordinationFake(),
          s = SessionController(f),
          w = CoordinationController(s, f, null);
      try {
        await sign(f, s, AppRole.coordinator);
        final pending = Completer<Json>();
        f.command = (name, fields, key) => coordinationReads.contains(name)
            ? Future.value(result(name))
            : pending.future;
        final action = w.run('warning', 'setPlaceWarning', {
          'placeId': 'place_hall',
          'warning': {
            'level': 'warning',
            'text': 'Ramp review',
            'expiresAt': '2026-10-23T01:00:00Z',
          },
        });
        expect(await w.run('warning', 'setPlaceWarning', {}), false);
        expect(
          () => (w.actions['warning']!.fields['warning'] as Map)['text'] =
              'mutated',
          throwsUnsupportedError,
        );
        pending.completeError(const BackendFailure('unavailable'));
        expect(await action, false);
        final before = f.coordCalls
            .where((e) => e.$1 == 'setPlaceWarning')
            .single;
        f.command = (name, fields, key) async => result(name);
        expect(
          await w.run('warning', 'setPlaceWarning', {'placeId': 'changed'}),
          true,
        );
        final after = f.coordCalls.where((e) => e.$1 == 'setPlaceWarning').last;
        expect(after.$3, before.$3);
        expect(after.$2, before.$2);
      } finally {
        w.dispose();
        s.dispose();
        await f.close();
      }
    },
  );
  test(
    'family notice queries separate consent scopes; withdrawal clears only permitted visible information',
    () async {
      final f = CoordinationFake(),
          s = SessionController(f),
          w = CoordinationController(s, f, null);
      try {
        await sign(f, s, AppRole.family);
        final old = w.viewToken;
        expect(
          f.scopes,
          contains('notices/family_demo/elder_demo/daily_sharing'),
        );
        expect(
          f.scopes,
          contains('notices/family_demo/elder_demo/family_booking'),
        );
        expect(w.progress['elder'], isNotNull);
        f.householdEvents.add(
          auth.household(f.current, sharing: false, booking: true),
        );
        await flush();
        expect(w.viewToken, isNot(old));
        expect(w.progress['elder'], isNull);
        expect(w.mayBook, true);
        expect(w.mayShare, false);
        expect(w.cheers, isEmpty);
        expect(f.cancelled, greaterThan(0));
        final before = f.scopes.length;
        w.retry();
        await flush();
        expect(
          f.scopes.skip(before).where((s) => s.endsWith('daily_sharing')),
          isEmpty,
        );
        expect(
          f.scopes.skip(before),
          contains('notices/family_demo/elder_demo/family_booking'),
        );
      } finally {
        w.dispose();
        s.dispose();
        await f.close();
      }
    },
  );
  test(
    'booking withdrawal rejects late voice draft while sharing progress stays available',
    () async {
      final f = CoordinationFake(),
          s = SessionController(f),
          w = CoordinationController(s, f, null);
      try {
        await sign(f, s, AppRole.family);
        final delayed = Completer<Json>();
        f.command = (name, fields, key) => name == 'parseVoiceBooking'
            ? delayed.future
            : Future.value(result(name));
        final parsing = w.parseVoice({
          'type': 'text',
          'text': 'Walk tomorrow',
        }, 'en');
        f.householdEvents.add(
          auth.household(f.current, sharing: true, booking: false),
        );
        await flush();
        delayed.complete(result('parseVoiceBooking'));
        await parsing;
        expect(w.voice, isNull);
        expect(w.mayBook, false);
        expect(w.mayShare, true);
        expect(w.progress['elder'], isNotNull);
      } finally {
        w.dispose();
        s.dispose();
        await f.close();
      }
    },
  );
  test(
    'logout clears records and ignores late report completion and snapshots',
    () async {
      final f = CoordinationFake(),
          s = SessionController(f),
          w = CoordinationController(s, f, null);
      try {
        await sign(f, s, AppRole.elder);
        final delayed = Completer<Json>();
        f.command = (name, fields, key) => coordinationReads.contains(name)
            ? Future.value(result(name))
            : delayed.future;
        final saving = w.run('report', 'submitReport', {
          'kind': 'place_problem',
          'placeId': 'place_hall',
          'text': 'Access review',
        });
        await s.signOut();
        delayed.complete(result('submitReport'));
        expect(await saving, false);
        f.emitCoord();
        expect(w.reports, isEmpty);
        expect(w.notices, isEmpty);
        expect(w.actions, isEmpty);
        expect(w.viewToken, isNull);
        expect(w.progress, isEmpty);
      } finally {
        w.dispose();
        s.dispose();
        await f.close();
      }
    },
  );
  test(
    'wrong-owner report and notice records fail closed; permission errors remove affected data',
    () async {
      final f = CoordinationFake(),
          s = SessionController(f),
          w = CoordinationController(s, f, null);
      try {
        await sign(f, s, AppRole.elder);
        f.events['reports/elder_demo/unlinked']!.add([
          {
            ...jsonObject(result('submitReport')['report']),
            'createdBy': 'another_person',
          },
        ]);
        expect(w.reports, isEmpty);
        expect(w.errors['reports:unlinked']!.code, 'permission-denied');
        f.events['notices/elder_demo/elder_demo/none']!.addError(
          const BackendFailure('permission-denied'),
        );
        expect(w.notices, isEmpty);
        expect(w.errors['notices:elder_demo:none']!.code, 'permission-denied');
      } finally {
        w.dispose();
        s.dispose();
        await f.close();
      }
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
    CoordinationFake f,
    SessionController s,
    AppRole role,
  ) async {
    await t.runAsync(() => sign(f, s, role));
    f.emitCommunity();
    f.emitWallet();
    f.emitCoord();
    await t.pumpAndSettle();
  }

  Future<void> finish(
    WidgetTester t,
    PreviewController c,
    SessionController s,
    MockEmasRepository mock,
    CoordinationFake f,
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
    'provider-unavailable UI shows honest manual fallback and never creates a fixture booking',
    (t) async {
      desktop(t);
      final f = CoordinationFake()..voiceUnavailable = true,
          s = SessionController(f),
          mock = MockEmasRepository(),
          c = PreviewController(mock, session: s);
      try {
        await t.pumpWidget(EmasCareApp(controller: c));
        await login(t, f, s, AppRole.elder);
        c.navigate(destination: Destination.companion);
        await t.pumpAndSettle();
        await tap(t, find.byKey(const ValueKey('stage6-voice')));
        await t.enterText(
          find.byType(TextField).first,
          'Walk with me tomorrow',
        );
        await tap(t, find.byKey(const ValueKey('parse-voice-booking')));
        expect(
          find.textContaining('not configured on this local backend'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('confirm-voice-request')),
          findsNothing,
        );
        expect(f.calls, isEmpty);
        await tap(t, find.byKey(const ValueKey('voice-manual-fallback')));
        expect(find.text('A little company, arranged.'), findsOneWidget);
        expect(f.calls, isEmpty);
      } finally {
        await finish(t, c, s, mock, f);
      }
    },
  );
  testWidgets(
    'injected voice fixture requires separate confirmation before existing createRequest flow',
    (t) async {
      desktop(t);
      final f = CoordinationFake(),
          s = SessionController(f, clock: () => DateTime.utc(2026, 10, 22)),
          mock = MockEmasRepository(),
          c = PreviewController(mock, session: s);
      try {
        await t.pumpWidget(EmasCareApp(controller: c));
        await login(t, f, s, AppRole.elder);
        c.navigate(destination: Destination.companion);
        await t.pumpAndSettle();
        await tap(t, find.byKey(const ValueKey('stage6-voice')));
        await t.enterText(find.byType(TextField).first, 'Walk tomorrow');
        await tap(t, find.byKey(const ValueKey('parse-voice-booking')));
        expect(f.calls, isEmpty);
        expect(
          find.byKey(const ValueKey('confirm-voice-request')),
          findsOneWidget,
        );
        await tap(t, find.byKey(const ValueKey('confirm-voice-request')));
        expect(f.calls.where((e) => e.$1 == 'create').length, 1);
        expect(f.calls.single.$2['elderId'], 'elder_demo');
      } finally {
        await finish(t, c, s, mock, f);
      }
    },
  );
  testWidgets(
    'report review captures details before a single confirmed mutation',
    (t) async {
      desktop(t);
      final f = CoordinationFake(),
          s = SessionController(f),
          mock = MockEmasRepository(),
          c = PreviewController(mock, session: s);
      try {
        await t.pumpWidget(EmasCareApp(controller: c));
        await login(t, f, s, AppRole.elder);
        await tap(t, find.byKey(const ValueKey('stage6-reports')));
        await tap(t, find.byKey(const ValueKey('submit-report')));
        await t.enterText(
          find
              .descendant(
                of: find.byType(CoordinationForm),
                matching: find.byType(TextField),
              )
              .last,
          'Please review the ramp access.',
        );
        await tap(t, find.widgetWithText(EmasButton, 'Review details'));
        expect(f.coordCalls.where((e) => e.$1 == 'submitReport'), isEmpty);
        await tap(t, find.byKey(const ValueKey('confirm-coordination-action')));
        expect(f.coordCalls.where((e) => e.$1 == 'submitReport').length, 1);
        expect(
          c.coordination!.reports.single.text,
          'Please review the ramp access.',
        );
      } finally {
        await finish(t, c, s, mock, f);
      }
    },
  );
  testWidgets(
    'Stage 6 panels fit BM larger text on phone, tablet and desktop for every role',
    (t) async {
      for (final width in [320.0, 390.0, 768.0, 1440.0]) {
        t.view.physicalSize = Size(width, 1100);
        t.view.devicePixelRatio = 1;
        for (final role in AppRole.values) {
          final f = CoordinationFake(),
              s = SessionController(f),
              mock = MockEmasRepository(),
              c = PreviewController(mock, session: s);
          try {
            await t.pumpWidget(EmasCareApp(controller: c));
            await login(t, f, s, role);
            c.toggleLanguage();
            c.setPreferences(text: true, motion: true, solid: true);
            await t.pumpAndSettle();
            await tap(t, find.byKey(const ValueKey('stage6-progress')));
            expect(t.takeException(), isNull, reason: 'progress $width $role');
            await tap(t, find.widgetWithText(ChoiceChip, 'Laporan & tempat'));
            expect(t.takeException(), isNull, reason: 'reports $width $role');
            if (role == AppRole.coordinator) {
              await tap(t, find.widgetWithText(ChoiceChip, 'Operasi'));
              expect(t.takeException(), isNull, reason: 'operations $width');
            }
            await tap(t, find.byTooltip('Tutup'));
          } finally {
            await finish(t, c, s, mock, f);
          }
        }
      }
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
}

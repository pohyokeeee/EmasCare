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
import 'package:emas_care/app/session_workflow_controller.dart';
import 'package:emas_care/data/backend_failure.dart';
import 'package:emas_care/data/emas_repository.dart';
import 'package:emas_care/data/session_repository.dart';
import 'package:emas_care/models/backend_models.dart';
import 'package:emas_care/models/community_models.dart';
import 'package:emas_care/models/preview_models.dart';
import 'package:emas_care/models/session_models.dart';
import 'package:emas_care/shared/design_system.dart';
import 'backend_test.dart' as auth;
import 'phase2_test.dart' as community;

final fixtures = jsonObject(
  jsonDecode(File('../docs/fixtures/stage3_sessions.json').readAsStringSync()),
);
Json result(String step, [String field = 'request']) =>
    jsonObject(jsonObject(jsonObject(fixtures[step])['output'])['data'])[field]
        as Json;
final testNow = DateTime.utc(2026, 10, 21);

class Stage3Fake extends community.CommunityFake implements SessionRepository {
  final requestEvents = StreamController<List<SessionRequest>>.broadcast(
    sync: true,
  );
  final List<(String, Json, String)> calls = [];
  final List<String> requestScopes = [];
  final Map<String, Json> rows = {};
  Json helper = result('availability', 'helperProfile');
  BackendProfile? queryProfile;
  String? queryElder;
  RequestState queryState = RequestState.requested;
  Future<SessionRequest> Function(String, Json, String)? mutation;
  @override
  Stream<List<SessionRequest>> watchRequests(
    BackendProfile profile, {
    String? elderId,
    RequestState queue = RequestState.requested,
  }) {
    queryProfile = profile;
    queryElder = elderId;
    queryState = queue;
    requestScopes.add(
      '${profile.role.name}/${profile.uid}/${profile.householdId}/$elderId/${queue.wire}',
    );
    return requestEvents.stream;
  }

  void emitRequests() {
    final p = queryProfile;
    if (p == null) return;
    requestEvents.add(
      rows.values
          .where(
            (r) => switch (p.role) {
              AppRole.elder => r['elderId'] == p.uid,
              AppRole.family =>
                r['elderId'] == queryElder && r['householdId'] == p.householdId,
              AppRole.helper =>
                r['helperId'] == p.uid && r['townshipId'] == p.townshipId,
              AppRole.coordinator =>
                r['townshipId'] == p.townshipId &&
                    r['state'] == queryState.wire,
            },
          )
          .map(SessionRequest.fromJson)
          .toList(),
    );
  }

  void emitCommunity() {
    settingsEvents.add(auth.settings());
    checkinEvents.add([]);
    exceptionEvents.add([]);
    activityEvents.add([
      ActivityRecord.fromJson({
        'id': 'activity_garden',
        'townshipId': 'township_demo',
        'title': {'en': 'Garden walk', 'bm': 'Jalan kebun'},
        'placeId': 'place_garden',
        'startsAt': '2026-10-22T01:00:00.000Z',
        'endsAt': '2026-10-22T02:00:00.000Z',
        'language': 'en',
        'participationMode': 'in_person',
      }),
    ]);
    placeEvents.add([
      PlaceRecord.fromJson({
        'id': 'place_garden',
        'townshipId': 'township_demo',
        'name': 'Community Garden',
        'stepFree': true,
      }),
    ]);
    pairingEvents.add([
      PairingRecord.fromJson({
        'id': 'pairing_demo',
        'townshipId': 'township_demo',
        'elderId': 'elder_demo',
        'helperId': 'helper_demo',
        'active': true,
        'elderAccepted': true,
        'helperAccepted': true,
        'trialStartsOn': '2026-10-20',
        'trialEndsOn': '2026-11-04',
      }),
    ]);
    helperEvents.add(HelperProfileRecord.fromJson(helper));
    emitRequests();
  }

  @override
  Future<HelperProfileRecord> setHelperAvailability(
    Json fields,
    String key,
  ) async {
    calls.add(('availability', fields, key));
    helper = {
      ...helper,
      'available': fields['available'],
      'availabilitySlots': fields['slots'],
    };
    final record = HelperProfileRecord.fromJson(helper);
    helperEvents.add(record);
    return record;
  }

  Future<SessionRequest> _mutate(String kind, Json fields, String key) async {
    calls.add((kind, fields, key));
    if (mutation != null) return mutation!(kind, fields, key);
    late Json row;
    if (kind == 'create') {
      final id = 'request_${rows.length + 1}';
      row = {
        ...result('create'),
        ...fields,
        'id': id,
        'createdBy': current.uid,
      };
    } else {
      row = {...rows[fields['requestId']]!};
      if (kind == 'assign') {
        row.addAll({
          'pairingId': fields['pairingId'],
          'helperId': 'helper_demo',
          'helperDisplay': {'displayName': 'Demo Helper', 'tier': 'T3'},
          'state': 'assigned',
        });
      } else {
        final action = fields['action'];
        row['state'] = switch (action) {
          'accept' => 'accepted',
          'start' => 'in_progress',
          'finish' => 'awaiting_confirmation',
          'cancel' => 'cancelled',
          _ => row['state'],
        };
        if (action == 'confirm') {
          row[current.role == AppRole.elder
              ? 'elderConfirmation'
              : 'helperConfirmation'] = {
            'uid': current.uid,
            'at': testNow.toIso8601String(),
          };
          if (row['elderConfirmation'] != null &&
              row['helperConfirmation'] != null) {
            row['state'] = 'completed';
            row['completedAt'] = testNow.toIso8601String();
          }
        }
      }
    }
    rows[row['id'] as String] = row;
    emitRequests();
    return SessionRequest.fromJson(row);
  }

  @override
  Future<SessionRequest> createRequest(Json fields, String key) =>
      _mutate('create', fields, key);
  @override
  Future<SessionRequest> assignRequest(Json fields, String key) =>
      _mutate('assign', fields, key);
  @override
  Future<SessionRequest> transitionRequest(Json fields, String key) =>
      _mutate('transition', fields, key);
  @override
  Future<void> close() async {
    await super.close();
    await requestEvents.close();
  }
}

Future<void> signAs(
  Stage3Fake fake,
  SessionController session,
  AppRole role, {
  bool booking = true,
  bool sharing = true,
}) async {
  if (session.profile != null) await session.signOut();
  fake.current = auth.profile(role, '${role.name}_demo');
  await session.signIn('demo@test', 'demo');
  await Future<void>.delayed(Duration.zero);
  if (role == AppRole.family) {
    fake.householdEvents.add(
      auth.household(fake.current, booking: booking, sharing: sharing),
    );
  }
  fake.emitCommunity();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Manrope');
    for (final weight in [400, 500, 600, 700]) {
      loader.addFont(rootBundle.load('assets/fonts/Manrope-$weight.ttf'));
    }
    await loader.load();
  });
  test(
    'all Stage 3 fixture states and nested confirmation timestamps parse consistently',
    () {
      Object? firestore(Object? value) => value is Map
          ? value.map((k, v) => MapEntry(k, firestore(v)))
          : value is String && RegExp(r'^2026-\d\d-\d\dT').hasMatch(value)
          ? Timestamp.fromDate(DateTime.parse(value))
          : value;
      for (final step in [
        'create',
        'assign',
        'accept',
        'start',
        'finish',
        'helperConfirm',
        'elderConfirm',
      ]) {
        final record = SessionRequest.fromJson(result(step));
        final timestampRecord = SessionRequest.fromJson(
          jsonObject(firestore(result(step))),
        );
        expect(timestampRecord.state, record.state);
        expect(timestampRecord.startsAt, record.startsAt);
        expect(
          timestampRecord.helperConfirmation?.at,
          record.helperConfirmation?.at,
        );
        expect(timestampRecord.completedAt, record.completedAt);
      }
      final complete = SessionRequest.fromJson(result('elderConfirm'));
      expect(complete.elderConfirmed && complete.helperConfirmed, true);
      expect(complete.completedAt, complete.elderConfirmation!.at);
      final helper = HelperProfileRecord.fromJson(
        result('availability', 'helperProfile'),
      );
      expect(helper.slots.last['endMinute'], 1440);
      expect(helper.updatedAt, DateTime.parse(fixtures['serverTime']));
    },
  );
  test(
    'failed mutations retain a deep frozen payload/key; duplicate taps do not send; new action gets a new key',
    () async {
      final fake = Stage3Fake();
      final s = SessionController(fake, clock: () => testNow),
          w = SessionWorkflowController(s, fake);
      await signAs(fake, s, AppRole.elder);
      final gate = Completer<SessionRequest>();
      fake.mutation = (_, _, _) => gate.future;
      final fields = jsonObject(jsonObject(fixtures['create'])['input'])
        ..remove('contractVersion')
        ..remove('idempotencyKey');
      final first = w.run('create:a', 'create', fields);
      expect(
        await w.run('create:a', 'create', {
          ...fields,
          'preferredLanguage': 'bm',
        }),
        false,
      );
      expect(fake.calls.length, 1);
      fields['preferredLanguage'] = 'bm';
      gate.completeError(const BackendFailure('unavailable'));
      expect(await first, false);
      fake.mutation = (_, _, _) async =>
          SessionRequest.fromJson(result('create'));
      expect(await w.retryAction('create:a'), true);
      expect(fake.calls[0].$3, fake.calls[1].$3);
      expect(fake.calls[1].$2['preferredLanguage'], 'en');
      await w.run('create:b', 'create', fields);
      expect(fake.calls.last.$3, isNot(fake.calls.first.$3));
      final action = WorkflowAction('availability', {
        'slots': [
          {'weekday': 1, 'startMinute': 0, 'endMinute': 1440},
        ],
      });
      expect(
        () => (action.fields['slots'] as List).first['weekday'] = 2,
        throwsUnsupportedError,
      );
      w.dispose();
      s.dispose();
      await fake.close();
    },
  );
  test('late mutation responses cannot restore state after sign-out', () async {
    final fake = Stage3Fake();
    final session = SessionController(fake, clock: () => testNow),
        w = SessionWorkflowController(session, fake);
    await signAs(fake, session, AppRole.elder);
    final gate = Completer<SessionRequest>();
    fake.mutation = (_, _, _) => gate.future;
    final pending = w.run('create:a', 'create', {});
    await session.signOut();
    gate.complete(SessionRequest.fromJson(result('create')));
    expect(await pending, false);
    expect(w.requests, isEmpty);
    expect(w.actions, isEmpty);
    w.dispose();
    session.dispose();
    await fake.close();
  });

  test(
    'stale callable responses cannot replace a newer stream; permission errors clear private state',
    () async {
      final fake = Stage3Fake();
      final s = SessionController(fake, clock: () => testNow);
      final w = SessionWorkflowController(s, fake);
      await signAs(fake, s, AppRole.elder);
      fake.rows['r'] = {...result('create'), 'id': 'r'};
      fake.emitRequests();
      final gate = Completer<SessionRequest>();
      fake.mutation = (_, _, _) => gate.future;
      final pending = w.transition('r', 'cancel');
      fake.rows['r'] = {...result('elderConfirm'), 'id': 'r'};
      fake.emitRequests();
      gate.complete(SessionRequest.fromJson(result('create')));
      expect(await pending, true);
      expect(w.requests.single.state, RequestState.completed);
      fake.mutation = (_, _, _) async =>
          throw const BackendFailure('permission-denied', 'CONSENT_REQUIRED');
      expect(await w.transition('r', 'confirm'), false);
      expect(w.requests, isEmpty);
      expect(w.actions, isEmpty);
      expect(w.error?.reason, 'CONSENT_REQUIRED');
      fake.emitRequests();
      expect(w.requests, isEmpty);
      w.dispose();
      s.dispose();
      await fake.close();
    },
  );
  test(
    'family request scope depends on booking, independently of sharing, and clears on withdrawal/denial',
    () async {
      final fake = Stage3Fake();
      final s = SessionController(fake, clock: () => testNow);
      final actual = SessionWorkflowController(s, fake);
      await signAs(fake, s, AppRole.family, booking: false, sharing: true);
      expect(fake.requestScopes, isEmpty);
      fake.householdEvents.add(
        auth.household(fake.current, booking: true, sharing: false),
      );
      expect(
        fake.requestScopes.single,
        contains('/household_demo/elder_demo/'),
      );
      fake.rows['r'] = {...result('create'), 'id': 'r'};
      fake.emitRequests();
      expect(actual.requests.length, 1);
      fake.householdEvents.add(auth.household(fake.current, booking: false));
      expect(actual.requests, isEmpty);
      fake.emitRequests();
      expect(actual.requests, isEmpty);
      fake.householdEvents.add(auth.household(fake.current, booking: true));
      fake.emitRequests();
      fake.requestEvents.addError(const BackendFailure('permission-denied'));
      expect(actual.requests, isEmpty);
      expect(actual.error?.code, 'permission-denied');
      fake.emitRequests();
      expect(actual.requests, isEmpty);
      actual.dispose();
      s.dispose();
      await fake.close();
    },
  );
  for (final role in [AppRole.elder, AppRole.helper, AppRole.coordinator]) {
    test(
      '${role.name} request scope follows the authenticated role and coordinator queue',
      () async {
        final fake = Stage3Fake();
        final s = SessionController(fake, clock: () => testNow);
        final w = SessionWorkflowController(s, fake);
        await signAs(fake, s, role);
        expect(
          fake.requestScopes.single,
          startsWith('${role.name}/${role.name}_demo/'),
        );
        if (role == AppRole.coordinator) {
          w.selectQueue(RequestState.completed);
          expect(fake.requestScopes.last, endsWith('/completed'));
        }
        w.dispose();
        s.dispose();
        await fake.close();
      },
    );
  }
  test(
    'business errors explain timing, reservations and validation without blaming connectivity',
    () {
      for (final reason in [
        'HELPER_UNAVAILABLE',
        'HELPER_BUSY',
        'PAIRING_NOT_ELIGIBLE',
        'INVALID_TRANSITION',
        'SESSION_NOT_STARTED',
        'ACTIVITY_NOT_FINISHED',
        'INVALID_AVAILABILITY',
        'ACTIVITY_REQUEST_EXISTS',
      ]) {
        final failure = BackendFailure('failed-precondition', reason);
        expect(failure.message(false), isNot(contains('Could not reach')));
        expect(
          failure.message(true),
          isNot(contains('Tidak dapat menghubungi')),
        );
      }
    },
  );

  Future<void> tap(WidgetTester tester, Finder finder) async {
    final target = tester.widget(finder) is EmasButton
        ? find.descendant(of: finder, matching: find.byType(Text)).first
        : finder;
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> login(
    WidgetTester tester,
    Stage3Fake fake,
    SessionController session,
    AppRole role, {
    bool sharing = true,
  }) async {
    await tester.runAsync(() => signAs(fake, session, role, sharing: sharing));
    // Auth callbacks bind streams in the widget-test zone. Deliver their initial
    // snapshots after that frame, as a Firestore listener does on subscription.
    await tester.pump();
    if (role == AppRole.family) {
      fake.householdEvents.add(auth.household(fake.current, sharing: sharing));
    }
    fake.emitCommunity();
    await tester.pump();
  }

  testWidgets(
    'live booking, assignment, schedule gates and separate confirmations cross authenticated roles',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var clock = testNow;
      final fake = Stage3Fake(), mock = MockEmasRepository();
      final s = SessionController(fake, clock: () => clock);
      final c = PreviewController(mock, session: s);
      await tester.pumpWidget(EmasCareApp(controller: c));
      Future<void> role(AppRole role) async {
        await login(tester, fake, s, role);
        expect(
          c.sessions!.loading,
          false,
          reason: 'requests loaded for ${role.name}: ${fake.requestScopes}',
        );
        expect(
          c.community!.catalogLoading,
          false,
          reason: 'catalog loaded for ${role.name}',
        );
        c.navigate(
          destination: role == AppRole.coordinator
              ? Destination.activities
              : Destination.companion,
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.byType(LinearProgressIndicator),
          findsNothing,
          reason:
              '${role.name}: requests=${c.sessions!.loading}, catalog=${c.community!.catalogLoading}, pairing=${c.community!.pairingLoading}, profile=${s.loading}, domain=${s.dataLoading}, destination=${c.destination}',
        );
        expect(
          find.byType(CircularProgressIndicator),
          findsNothing,
          reason: '${role.name}: profile=${s.loading}, busy=${s.authBusy}',
        );
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
      }

      await role(AppRole.elder);
      c.navigate(destination: Destination.activities);
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const ValueKey('activity-activity_garden')));
      await tap(tester, find.text('Request a companion'));
      expect(find.text('Anything helpful to know? (optional)'), findsNothing);
      await tap(tester, find.byKey(const ValueKey('review-request')));
      await tap(tester, find.byKey(const ValueKey('send-live-request')));
      expect(fake.rows.length, 1);
      expect(fake.calls.last.$2.keys.toSet(), {
        'elderId',
        'activityId',
        'placeId',
        'startsAt',
        'endsAt',
        'taskType',
        'preferredLanguage',
        'preferredHelperGender',
      });
      expect(fake.calls.last.$2['endsAt'], '2026-10-22T02:00:00.000Z');
      await role(AppRole.coordinator);
      await tap(tester, find.text('Choose companion'));
      await tap(tester, find.byKey(const ValueKey('assign-live-companion')));
      expect(fake.rows.values.single['state'], 'assigned');
      await role(AppRole.helper);
      await tap(tester, find.text('Accept session'));
      expect(
        tester
            .widget<EmasButton>(
              find.widgetWithText(EmasButton, 'Start session'),
            )
            .onPressed,
        isNull,
      );
      clock = DateTime.utc(2026, 10, 22, 1);
      await tester.pump(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Start session'));
      expect(
        tester
            .widget<EmasButton>(
              find.widgetWithText(EmasButton, 'Finish session'),
            )
            .onPressed,
        isNull,
      );
      clock = DateTime.utc(2026, 10, 22, 2);
      await tester.pump(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Finish session'));
      await tap(tester, find.text('Confirm my participation'));
      expect(fake.rows.values.single['state'], 'awaiting_confirmation');
      await role(AppRole.family);
      expect(find.text('Confirm my participation'), findsNothing);
      await role(AppRole.elder);
      await tap(tester, find.text('Confirm my participation'));
      expect(find.text('Confirmed by both'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      s.dispose();
      mock.dispose();
      await fake.close();
    },
  );
  testWidgets(
    'helper saves full-day availability; overlapping added intervals are rejected before sending',
    (tester) async {
      final fake = Stage3Fake(), mock = MockEmasRepository();
      final s = SessionController(fake, clock: () => testNow);
      final c = PreviewController(mock, session: s);
      await tester.pumpWidget(EmasCareApp(controller: c));
      await login(tester, fake, s, AppRole.helper);
      await tester.pumpAndSettle();
      await tap(tester, find.text('Edit availability'));
      await tap(
        tester,
        find.widgetWithText(SwitchListTile, 'Available to help'),
      );
      await tap(tester, find.byKey(const ValueKey('save-live-availability')));
      expect(fake.helper['available'], false);
      expect((fake.calls.last.$2['slots'] as List).length, 7);
      await tap(tester, find.text('Edit availability'));
      await tap(tester, find.text('Add weekly interval'));
      await tap(tester, find.byKey(const ValueKey('save-live-availability')));
      expect(find.text('Weekly intervals cannot overlap.'), findsOneWidget);
      expect(fake.calls.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      s.dispose();
      mock.dispose();
      await fake.close();
    },
  );

  testWidgets(
    'standalone phone help sends explicit null IDs and no preview-only fields; cancellation persists',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = Stage3Fake(), mock = MockEmasRepository();
      final s = SessionController(fake, clock: () => testNow);
      final c = PreviewController(mock, session: s);
      await tester.pumpWidget(EmasCareApp(controller: c));
      await login(tester, fake, s, AppRole.elder);
      c.navigate(destination: Destination.companion);
      await tester.pumpAndSettle();
      await tap(tester, find.text('New request'));
      await tap(tester, find.text('Phone help'));
      await tap(tester, find.byKey(const ValueKey('review-request')));
      await tap(tester, find.byKey(const ValueKey('send-live-request')));
      expect(fake.calls.single.$2['activityId'], isNull);
      expect(fake.calls.single.$2['placeId'], isNull);
      expect(fake.calls.single.$2['taskType'], 'phone_help');
      expect(c.demo.requests, isEmpty);
      await tap(tester, find.widgetWithText(TextButton, 'Cancel request'));
      await tap(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancel request'),
        ),
      );
      expect(fake.rows.values.single['state'], 'cancelled');
      expect(find.text('Cancelled'), findsOneWidget);
      expect(fake.calls.last.$2, {
        'requestId': 'request_1',
        'action': 'cancel',
      });
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      s.dispose();
      mock.dispose();
      await fake.close();
    },
  );

  testWidgets(
    'assignment retry survives an earlier queue update and never navigates a dismissed sheet',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = Stage3Fake(), mock = MockEmasRepository();
      final s = SessionController(fake, clock: () => testNow);
      final c = PreviewController(mock, session: s);
      await tester.pumpWidget(EmasCareApp(controller: c));
      await login(tester, fake, s, AppRole.coordinator);
      c.navigate(destination: Destination.activities);
      await tester.pumpAndSettle();
      for (final dismiss in [false, true]) {
        final id = dismiss ? 'dismissed' : 'open';
        fake.rows[id] = {...result('create'), 'id': id};
        fake.emitRequests();
        await tester.pumpAndSettle();
        await tap(tester, find.text('Choose companion'));
        fake.mutation = (_, _, _) async => throw const BackendFailure(
          'failed-precondition',
          'HELPER_UNAVAILABLE',
        );
        await tap(tester, find.byKey(const ValueKey('assign-live-companion')));
        final originalKey = fake.calls.last.$3;
        final gate = Completer<SessionRequest>();
        final assigned = {...result('assign'), 'id': id};
        fake.mutation = (_, _, _) {
          fake.rows[id] = assigned;
          fake.emitRequests();
          return gate.future;
        };
        final retry = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Try again'),
        );
        await Scrollable.ensureVisible(tester.element(retry), alignment: .5);
        await tester.tap(retry);
        await tester.pump(const Duration(milliseconds: 300));
        expect(fake.calls.last.$3, originalKey);
        if (dismiss) {
          await tester.tap(find.byTooltip('Close'));
          await tester.pump(const Duration(milliseconds: 1));
        }
        gate.complete(SessionRequest.fromJson(assigned));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('Requests to arrange'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      s.dispose();
      mock.dispose();
      await fake.close();
    },
  );
  testWidgets(
    'live request draft hides on family booking withdrawal; sharing stays independent',
    (tester) async {
      final fake = Stage3Fake(), mock = MockEmasRepository();
      final s = SessionController(fake, clock: () => testNow);
      final c = PreviewController(mock, session: s);
      await tester.pumpWidget(EmasCareApp(controller: c));
      await login(tester, fake, s, AppRole.family, sharing: false);
      c.navigate(destination: Destination.companion);
      await tester.pumpAndSettle();
      await tap(tester, find.text('New request'));
      expect(find.text('A little company, arranged.'), findsOneWidget);
      fake.householdEvents.add(
        auth.household(fake.current, booking: false, sharing: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('A little company, arranged.'), findsNothing);
      expect(find.byKey(const ValueKey('send-live-request')), findsNothing);
      expect(c.sessions!.requests, isEmpty);
      fake.householdEvents.add(auth.household(fake.current, booking: true));
      fake.emitRequests();
      await tester.pumpAndSettle();
      expect(find.text('A little company, arranged.'), findsNothing);
      expect(find.byKey(const ValueKey('send-live-request')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      s.dispose();
      mock.dispose();
      await fake.close();
    },
  );
  testWidgets(
    'live sessions and request review fit every role in BM/larger text at phone and desktop widths',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = Stage3Fake(), mock = MockEmasRepository();
      final s = SessionController(fake, clock: () => testNow);
      final c = PreviewController(mock, session: s);
      await tester.pumpWidget(EmasCareApp(controller: c));
      for (final role in AppRole.values) {
        await login(tester, fake, s, role);
        c.malay = true;
        c.setPreferences(text: true, motion: true, solid: true);
        c.navigate(
          destination: role == AppRole.coordinator
              ? Destination.activities
              : Destination.companion,
        );
        for (final step in ['create', 'helperConfirm', 'elderConfirm']) {
          final row = {...result(step), 'id': 'r'};
          fake.rows.clear();
          fake.rows['r'] = row;
          if (role == AppRole.coordinator) {
            c.sessions!.selectQueue(RequestState.parse(row['state']));
          }
          fake.emitRequests();
          for (final width in [320.0, 390.0, 768.0, 1440.0]) {
            tester.view.physicalSize = Size(width, 1100);
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '${role.name}/$step at $width',
            );
          }
        }
        if (role == AppRole.elder || role == AppRole.family) {
          c.navigate(destination: Destination.activities);
          for (final width in [320.0, 390.0, 768.0, 1440.0]) {
            tester.view.physicalSize = Size(width, 1100);
            await tester.pumpAndSettle();
            await tap(
              tester,
              find.byKey(const ValueKey('activity-activity_garden')),
            );
            await tap(tester, find.widgetWithText(EmasButton, 'Minta teman'));
            await tap(tester, find.byKey(const ValueKey('review-request')));
            expect(
              tester.takeException(),
              isNull,
              reason: 'request ${role.name} at $width',
            );
            await tap(tester, find.byTooltip('Tutup'));
          }
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      s.dispose();
      mock.dispose();
      await fake.close();
    },
  );
}

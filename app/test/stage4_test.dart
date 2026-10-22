import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:emas_care/app/attendance_controller.dart';
import 'package:emas_care/app/emas_app.dart';
import 'package:emas_care/app/preview_controller.dart';
import 'package:emas_care/app/session_controller.dart';
import 'package:emas_care/data/attendance_repository.dart';
import 'package:emas_care/data/backend_failure.dart';
import 'package:emas_care/data/emas_repository.dart';
import 'package:emas_care/models/attendance_models.dart';
import 'package:emas_care/models/backend_models.dart';
import 'package:emas_care/models/community_models.dart';
import 'package:emas_care/models/preview_models.dart';
import 'package:emas_care/shared/design_system.dart';
import 'backend_test.dart' as auth;
import 'stage3_test.dart' as stage3;

final fixture = jsonObject(
  jsonDecode(
    File('../docs/fixtures/stage4_attendance.json').readAsStringSync(),
  ),
);
Json row(String step) => jsonObject(
  jsonObject(
    jsonObject(jsonObject(fixture[step])['output'])['data'],
  )['attendance'],
);
final now = DateTime.utc(2026, 10, 21);
const pastId = 'activity_demo_attendance';
ActivityRecord pastActivity({DateTime? end, String mode = 'in_person'}) =>
    ActivityRecord.fromJson({
      'id': pastId,
      'townshipId': 'township_demo',
      'title': {
        'en': 'Past community activity (demo)',
        'bm': 'Aktiviti komuniti lalu (demo)',
      },
      'placeId': 'place_garden',
      'startsAt': now.subtract(const Duration(hours: 2)).toIso8601String(),
      'endsAt': (end ?? now.subtract(const Duration(hours: 1)))
          .toIso8601String(),
      'language': 'en',
      'participationMode': mode,
    });

class AttendanceFake extends stage3.Stage3Fake implements AttendanceRepository {
  late final StreamController<List<ActivityAttendance>> attendanceEvents =
      StreamController.broadcast(
        sync: true,
        onCancel: () {
          attendanceCancels++;
        },
      );
  final Map<String, Json> attendanceRows = {};
  final List<(String, Json, String)> attendanceCalls = [];
  final List<String> attendanceScopes = [];
  int attendanceCancels = 0;
  BackendProfile? attendanceProfile;
  String? attendanceElder;
  ActivityRecord past = pastActivity();
  Future<ActivityAttendance> Function(String, Json, String)? attendanceMutation;
  @override
  Stream<List<ActivityAttendance>> watchAttendance(
    BackendProfile profile, {
    String? elderId,
  }) {
    attendanceProfile = profile;
    attendanceElder = elderId;
    attendanceScopes.add(
      '${profile.role.name}/${profile.uid}/${profile.townshipId}/${profile.householdId}/$elderId',
    );
    return attendanceEvents.stream;
  }

  void emitAttendance() {
    final p = attendanceProfile;
    if (p == null) return;
    attendanceEvents.add(
      attendanceRows.values
          .where(
            (r) => switch (p.role) {
              AppRole.elder => r['elderId'] == p.uid,
              AppRole.family =>
                r['elderId'] == attendanceElder &&
                    r['householdId'] == p.householdId,
              AppRole.coordinator =>
                r['townshipId'] == p.townshipId && r['status'] == 'submitted',
              AppRole.helper => false,
            },
          )
          .map(ActivityAttendance.fromJson)
          .toList(),
    );
  }

  @override
  void emitCommunity() {
    super.emitCommunity();
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
      past,
    ]);
    emitAttendance();
  }

  Future<ActivityAttendance> change(
    String kind,
    Json fields,
    String key,
  ) async {
    attendanceCalls.add((kind, fields, key));
    if (attendanceMutation != null) {
      return attendanceMutation!(kind, fields, key);
    }
    late Json record;
    if (kind == 'submit') {
      record = {
        ...row('submit'),
        'activityId': fields['activityId'],
        'elderId': current.uid,
      };
    } else {
      record = {
        ...attendanceRows[fields['attendanceId']]!,
        'status': fields['decision'] == 'verify' ? 'verified' : 'rejected',
        'verificationMethod': fields['verificationMethod'],
        'reviewNote': fields['note'],
        'reviewedBy': current.uid,
        'reviewedAt': now.toIso8601String(),
        'verifiedAt': fields['decision'] == 'verify'
            ? now.toIso8601String()
            : null,
      };
    }
    attendanceRows[record['id'] as String] = record;
    emitAttendance();
    return ActivityAttendance.fromJson(record);
  }

  @override
  Future<ActivityAttendance> submitActivityAttendance(
    Json fields,
    String key,
  ) => change('submit', fields, key);
  @override
  Future<ActivityAttendance> reviewActivityAttendance(
    Json fields,
    String key,
  ) => change('review', fields, key);
  @override
  Future<void> close() async {
    await super.close();
    await attendanceEvents.close();
  }
}

Future<void> signAs(
  AttendanceFake f,
  SessionController s,
  AppRole role, {
  bool sharing = true,
  bool booking = true,
}) async {
  await stage3.signAs(f, s, role, sharing: sharing, booking: booking);
  f.emitCommunity();
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
    'Stage 4 fixture records preserve every field and both timestamp representations',
    () {
      Object? convert(Object? v) => v is Map
          ? v.map((k, v) => MapEntry(k, convert(v)))
          : v is String && v.startsWith('2026-') && v.contains('T')
          ? Timestamp.fromDate(DateTime.parse(v))
          : v;
      for (final step in ['submit', 'verify', 'submitForRejection', 'reject']) {
        final input = row(step),
            a = ActivityAttendance.fromJson(input),
            b = ActivityAttendance.fromJson(jsonObject(convert(input)));
        expect(a.id, input['id']);
        expect(a.townshipId, input['townshipId']);
        expect(a.householdId, input['householdId']);
        expect(a.activityId, input['activityId']);
        expect(a.elderId, input['elderId']);
        expect(a.status.name, input['status']);
        expect(a.mode, input['mode']);
        expect(a.linkedRequestId, input['linkedRequestId']);
        expect(a.reviewNote, input['reviewNote']);
        expect(a.verificationMethod, input['verificationMethod']);
        expect(a.reviewedBy, input['reviewedBy']);
        expect(a.completionEventId, input['completionEventId']);
        expect(a.participationId, input['participationId']);
        expect(a.createdAt, b.createdAt);
        expect(a.updatedAt, b.updatedAt);
        expect(a.submittedAt, b.submittedAt);
        expect(a.verifiedAt, b.verifiedAt);
        expect(a.reviewedAt, b.reviewedAt);
        expect(a.reviewable, step == 'submit' || step == 'submitForRejection');
      }
      expect(
        ActivityAttendance.fromJson({
          ...row('verify'),
          'mode': 'companion_session',
          'submittedAt': null,
          'verificationMethod': 'mutual_session_confirmation',
        }).sessionManaged,
        true,
      );
    },
  );
  test(
    'submission retries keep a frozen payload and key; duplicate taps are ignored; new activity gets a new key',
    () async {
      final f = AttendanceFake(),
          s = SessionController(f, clock: () => now),
          w = AttendanceController(s, f);
      await signAs(f, s, AppRole.elder);
      final pending = Completer<ActivityAttendance>();
      f.attendanceMutation = (_, _, _) => pending.future;
      final first = w.submit(pastId);
      expect(await w.submit(pastId), false);
      expect(f.attendanceCalls.length, 1);
      pending.completeError(const BackendFailure('unavailable'));
      expect(await first, false);
      expect(
        () => w.actions['submit:$pastId']!.fields['activityId'] = 'forged',
        throwsUnsupportedError,
      );
      f.attendanceMutation = (_, _, _) async =>
          ActivityAttendance.fromJson(row('submit'));
      expect(await w.retryAction('submit:$pastId'), true);
      expect(f.attendanceCalls[0].$2, {'activityId': pastId});
      expect(f.attendanceCalls[1].$2, {'activityId': pastId});
      expect(f.attendanceCalls[0].$3, f.attendanceCalls[1].$3);
      await w.submit('another-occurrence');
      expect(f.attendanceCalls.last.$3, isNot(f.attendanceCalls.first.$3));
      w.dispose();
      s.dispose();
      await f.close();
    },
  );
  test(
    'review retries preserve the original decision, method and note while stream state remains authoritative',
    () async {
      final f = AttendanceFake(),
          s = SessionController(f, clock: () => now),
          w = AttendanceController(s, f);
      final submitted = row('submit');
      f.attendanceRows[submitted['id']] = submitted;
      await signAs(f, s, AppRole.coordinator);
      f.attendanceMutation = (_, _, _) async =>
          throw const BackendFailure('unavailable');
      final fields = {
        'decision': 'verify',
        'verificationMethod': 'organizer_roster',
        'note': 'Checked roster.',
      };
      await w.review(submitted['id'], fields);
      fields['note'] = 'Changed';
      f.attendanceMutation = (_, _, _) async {
        f.attendanceRows[submitted['id']] = {...row('verify')};
        f.emitAttendance();
        return ActivityAttendance.fromJson(submitted);
      };
      expect(
        await w.review(submitted['id'], {
          'decision': 'reject',
          'verificationMethod': null,
          'note': 'Changed',
        }),
        true,
      );
      expect(f.attendanceCalls.last.$2, {
        'attendanceId': submitted['id'],
        'decision': 'verify',
        'verificationMethod': 'organizer_roster',
        'note': 'Checked roster.',
      });
      expect(f.attendanceCalls.last.$3, f.attendanceCalls.first.$3);
      expect(w.records, isEmpty);
      await signAs(f, s, AppRole.elder);
      expect(w.records.single.status, AttendanceStatus.verified);
      w.dispose();
      s.dispose();
      await f.close();
    },
  );
  test(
    'family sharing gates attendance independently of booking and cancels/clears on withdrawal',
    () async {
      final f = AttendanceFake(),
          s = SessionController(f, clock: () => now),
          w = AttendanceController(s, f);
      f.attendanceRows[row('verify')['id']] = row('verify');
      await signAs(f, s, AppRole.family, sharing: true, booking: false);
      expect(w.records.single.status, AttendanceStatus.verified);
      expect(
        f.attendanceScopes.single,
        contains('family/family_demo/township_demo/household_demo/elder_demo'),
      );
      final token = w.viewToken;
      expect(await w.submit(pastId), false);
      expect(await w.review('id', {}), false);
      expect(f.attendanceCalls, isEmpty);
      f.householdEvents.add(
        auth.household(f.current, sharing: false, booking: true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(w.records, isEmpty);
      expect(w.viewToken, isNull);
      expect(f.attendanceCancels, 1);
      f.householdEvents.add(
        auth.household(f.current, sharing: true, booking: true),
      );
      f.emitAttendance();
      expect(w.records.length, 1);
      expect(w.viewToken, isNot(token));
      w.dispose();
      s.dispose();
      await f.close();
    },
  );
  test(
    'helper and unrelated family never subscribe; permission failure clears private records and blocks commands',
    () async {
      final f = AttendanceFake(),
          s = SessionController(f, clock: () => now),
          w = AttendanceController(s, f);
      await signAs(f, s, AppRole.helper);
      expect(f.attendanceScopes, isEmpty);
      expect(await w.submit(pastId), false);
      await signAs(f, s, AppRole.family, sharing: false);
      f.householdEvents.add(auth.household(f.current, linked: false));
      expect(f.attendanceScopes, isEmpty);
      await signAs(f, s, AppRole.elder);
      f.attendanceRows[row('verify')['id']] = row('verify');
      f.emitAttendance();
      expect(w.records.length, 1);
      f.attendanceEvents.addError(const BackendFailure('permission-denied'));
      expect(w.records, isEmpty);
      expect(w.viewToken, isNull);
      expect(w.error?.code, 'permission-denied');
      expect(await w.submit(pastId), false);
      w.retry();
      f.emitAttendance();
      expect(w.records.length, 1);
      expect(w.error, isNull);
      w.dispose();
      s.dispose();
      await f.close();
    },
  );
  test(
    'late mutation success after sign-out cannot restore old records or pending actions',
    () async {
      final f = AttendanceFake(),
          s = SessionController(f, clock: () => now),
          w = AttendanceController(s, f);
      await signAs(f, s, AppRole.elder);
      final reply = Completer<ActivityAttendance>();
      f.attendanceMutation = (_, _, _) => reply.future;
      final action = w.submit(pastId);
      await s.signOut();
      reply.complete(ActivityAttendance.fromJson(row('submit')));
      expect(await action, false);
      expect(w.actions, isEmpty);
      expect(w.records, isEmpty);
      expect(w.viewToken, isNull);
      w.dispose();
      s.dispose();
      await f.close();
    },
  );
  test('stable Stage 4 errors explain the required action in BM and EN', () {
    for (final reason in [
      'ATTENDANCE_MANAGED_BY_SESSION',
      'ATTENDANCE_ALREADY_REVIEWED',
      'INVALID_REVIEW_DECISION',
      'INVALID_VERIFICATION_METHOD',
      'INVALID_REVIEW_NOTE',
      'ACTIVITY_NOT_IN_PERSON',
      'INVALID_ATTENDANCE_LINK',
      'ATTENDANCE_NOT_FOUND',
      'ATTENDANCE_ACCESS_DENIED',
    ]) {
      final failure = BackendFailure('failed-precondition', reason);
      expect(failure.message(false), isNot(contains('Could not reach')));
      expect(failure.message(true), isNot(contains('Tidak dapat menghubungi')));
    }
  });
  test(
    'changing the selected family elder clears the old history before subscribing to the new scope',
    () async {
      final f = AttendanceFake(),
          s = SessionController(f, clock: () => now),
          w = AttendanceController(s, f);
      f.attendanceRows[row('verify')['id']] = row('verify');
      f.attendanceRows['second'] = {
        ...row('verify'),
        'id': 'second',
        'elderId': 'elder_second',
      };
      await signAs(f, s, AppRole.family);
      expect(w.records.single.elderId, 'elder_demo');
      f.householdEvents.add(
        HouseholdAccess.fromJson({
          'townshipId': 'township_demo',
          'memberUids': [f.current.uid],
          'familyUids': [f.current.uid],
          'elderIds': ['elder_demo', 'elder_second'],
          'elderAccess': {
            for (final id in ['elder_demo', 'elder_second'])
              id: {
                'displayName': id,
                'familySharingEnabled': true,
                'familyBookingEnabled': false,
              },
          },
        }, f.current),
      );
      s.selectElder('elder_second');
      expect(w.records, isEmpty);
      expect(w.loading, true);
      f.emitAttendance();
      expect(w.records.single.elderId, 'elder_second');
      expect(f.attendanceScopes.last, endsWith('/elder_second'));
      w.dispose();
      s.dispose();
      await f.close();
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
    AttendanceFake f,
    SessionController s,
    AppRole role, {
    bool sharing = true,
    bool booking = true,
  }) async {
    await t.runAsync(
      () => signAs(f, s, role, sharing: sharing, booking: booking),
    );
    await t.pump();
    if (role == AppRole.family) {
      f.householdEvents.add(
        auth.household(f.current, sharing: sharing, booking: booking),
      );
    }
    f.emitCommunity();
    await t.pumpAndSettle();
  }

  Future<void> choose(WidgetTester t, String key, String label) async {
    await tap(t, find.byKey(ValueKey(key)));
    await t.tap(find.text(label).last);
    await t.pumpAndSettle();
  }

  Future<void> dispose(
    WidgetTester t,
    PreviewController c,
    SessionController s,
    MockEmasRepository mock,
    AttendanceFake f,
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
    'elder submits ended attendance; coordinator validates evidence and verifies; permitted family sees saved history',
    (t) async {
      desktop(t);
      final f = AttendanceFake(),
          s = SessionController(f, clock: () => now),
          mock = MockEmasRepository(),
          c = PreviewController(mock, session: s);
      await t.pumpWidget(EmasCareApp(controller: c));
      await login(t, f, s, AppRole.elder);
      c.navigate(destination: Destination.activities);
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('activity-filter-3')));
      await tap(
        t,
        find.byKey(const ValueKey('activity-activity_demo_attendance')),
      );
      await tap(
        t,
        find.byKey(
          const ValueKey('submit-attendance-activity_demo_attendance'),
        ),
      );
      expect(f.attendanceCalls.single.$1, 'submit');
      expect(f.attendanceCalls.single.$2, {'activityId': pastId});
      expect(find.text('Awaiting verification'), findsOneWidget);
      expect(find.text('I attended'), findsNothing);
      await tap(t, find.byTooltip('Close'));
      await login(t, f, s, AppRole.coordinator);
      c.navigate(destination: Destination.activities);
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('attendance-review-tab')));
      await tap(
        t,
        find.byKey(ValueKey('review-attendance-${row('submit')['id']}')),
      );
      await tap(t, find.byKey(const ValueKey('save-attendance-review')));
      expect(f.attendanceCalls.length, 1);
      expect(find.text('Choose how you checked attendance.'), findsOneWidget);
      await choose(
        t,
        'attendance-review-method',
        'I checked the organizer roster',
      );
      await t.enterText(
        find.byKey(const ValueKey('attendance-review-note')),
        '  Matched the demo organizer roster.  ',
      );
      await tap(t, find.byKey(const ValueKey('save-attendance-review')));
      expect(f.attendanceCalls.last.$2, {
        'attendanceId': row('submit')['id'],
        'decision': 'verify',
        'verificationMethod': 'organizer_roster',
        'note': 'Matched the demo organizer roster.',
      });
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('All caught up.'), findsOneWidget);
      await login(t, f, s, AppRole.family, booking: false);
      c.navigate(destination: Destination.activities);
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('open-attendance-history')));
      expect(find.text('Verified attendance'), findsOneWidget);
      expect(find.text('Matched the demo organizer roster.'), findsOneWidget);
      expect(find.text('I attended'), findsNothing);
      expect(find.text('Save review'), findsNothing);
      expect(t.takeException(), isNull);
      await dispose(t, c, s, mock, f);
    },
  );
  testWidgets(
    'rejection sends null method and a reason; rejected history stays terminal',
    (t) async {
      desktop(t);
      final f = AttendanceFake(),
          s = SessionController(f, clock: () => now),
          mock = MockEmasRepository(),
          c = PreviewController(mock, session: s);
      f.attendanceRows[row('submit')['id']] = row('submit');
      await t.pumpWidget(EmasCareApp(controller: c));
      await login(t, f, s, AppRole.coordinator);
      c.navigate(destination: Destination.activities);
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('attendance-review-tab')));
      await tap(
        t,
        find.byKey(ValueKey('review-attendance-${row('submit')['id']}')),
      );
      await choose(t, 'attendance-review-method', 'I observed attendance');
      await choose(t, 'attendance-review-decision', 'Cannot verify');
      await t.enterText(
        find.byKey(const ValueKey('attendance-review-note')),
        'Not on the demo roster.',
      );
      await tap(t, find.byKey(const ValueKey('save-attendance-review')));
      expect(f.attendanceCalls.single.$2['verificationMethod'], isNull);
      expect(f.attendanceCalls.single.$2['decision'], 'reject');
      await login(t, f, s, AppRole.elder);
      c.navigate(destination: Destination.activities);
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('activity-filter-3')));
      await tap(
        t,
        find.byKey(const ValueKey('activity-activity_demo_attendance')),
      );
      expect(find.text('Not verified'), findsOneWidget);
      expect(find.text('Not on the demo roster.'), findsOneWidget);
      expect(find.text('I attended'), findsNothing);
      await dispose(t, c, s, mock, f);
    },
  );
  testWidgets(
    'sharing withdrawal clears attendance history immediately; booking permission cannot restore it',
    (t) async {
      desktop(t);
      final f = AttendanceFake(),
          s = SessionController(f, clock: () => now),
          mock = MockEmasRepository(),
          c = PreviewController(mock, session: s);
      f.attendanceRows[row('verify')['id']] = row('verify');
      await t.pumpWidget(EmasCareApp(controller: c));
      await login(t, f, s, AppRole.family, booking: false);
      c.navigate(destination: Destination.activities);
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('open-attendance-history')));
      expect(
        find.text('Matched the organizer attendance roster.'),
        findsOneWidget,
      );
      f.householdEvents.add(
        auth.household(f.current, sharing: false, booking: true),
      );
      await t.pumpAndSettle();
      expect(find.text('Attendance is private.'), findsOneWidget);
      expect(
        find.text('Matched the organizer attendance roster.'),
        findsNothing,
      );
      f.householdEvents.add(
        auth.household(f.current, sharing: true, booking: false),
      );
      f.emitAttendance();
      await t.pumpAndSettle();
      expect(find.text('Verified attendance'), findsOneWidget);
      expect(f.attendanceCalls, isEmpty);
      await dispose(t, c, s, mock, f);
    },
  );
  testWidgets(
    'future and online activities cannot be submitted; companion-managed attendance uses existing confirmations',
    (t) async {
      desktop(t);
      final f = AttendanceFake(),
          s = SessionController(f, clock: () => now),
          mock = MockEmasRepository(),
          c = PreviewController(mock, session: s);
      await t.pumpWidget(EmasCareApp(controller: c));
      await login(t, f, s, AppRole.elder);
      c.navigate(destination: Destination.activities);
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('activity-activity_garden')));
      expect(
        t
            .widget<EmasButton>(
              find.byKey(const ValueKey('submit-attendance-activity_garden')),
            )
            .onPressed,
        isNull,
      );
      await tap(t, find.byTooltip('Close'));
      f.past = pastActivity(mode: 'online');
      f.emitCommunity();
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('activity-filter-3')));
      await tap(
        t,
        find.byKey(const ValueKey('activity-activity_demo_attendance')),
      );
      expect(
        t
            .widget<EmasButton>(
              find.byKey(
                const ValueKey('submit-attendance-activity_demo_attendance'),
              ),
            )
            .onPressed,
        isNull,
      );
      await tap(t, find.byTooltip('Close'));
      f.past = pastActivity();
      f.rows['managed'] = {
        ...stage3.result('create'),
        'id': 'managed',
        'activityId': pastId,
      };
      f.emitCommunity();
      await t.pumpAndSettle();
      await tap(
        t,
        find.byKey(const ValueKey('activity-activity_demo_attendance')),
      );
      expect(find.text('I attended'), findsNothing);
      expect(find.text('Open My companion'), findsOneWidget);
      f.attendanceRows[row('verify')['id']] = {
        ...row('verify'),
        'mode': 'companion_session',
        'submittedAt': null,
        'verificationMethod': 'mutual_session_confirmation',
        'reviewNote': null,
      };
      f.emitAttendance();
      await t.pumpAndSettle();
      expect(
        find.text('Recorded through both companion-session confirmations.'),
        findsOneWidget,
      );
      expect(find.text('I attended'), findsNothing);
      expect(f.attendanceCalls, isEmpty);
      await dispose(t, c, s, mock, f);
    },
  );
  testWidgets(
    'an activity becomes eligible at its exact end while its detail sheet remains open',
    (t) async {
      desktop(t);
      var clock = now;
      final f = AttendanceFake(),
          s = SessionController(f, clock: () => clock),
          mock = MockEmasRepository(),
          c = PreviewController(mock, session: s);
      f.past = pastActivity(end: now.add(const Duration(minutes: 1)));
      await t.pumpWidget(EmasCareApp(controller: c));
      await login(t, f, s, AppRole.elder);
      c.navigate(destination: Destination.activities);
      await t.pumpAndSettle();
      await tap(
        t,
        find.byKey(const ValueKey('activity-activity_demo_attendance')),
      );
      final action = find.byKey(
        const ValueKey('submit-attendance-activity_demo_attendance'),
      );
      expect(t.widget<EmasButton>(action).onPressed, isNull);
      clock = now.add(const Duration(minutes: 1));
      await t.pump(const Duration(minutes: 1));
      await t.pumpAndSettle();
      expect(t.widget<EmasButton>(action).onPressed, isNotNull);
      await dispose(t, c, s, mock, f);
    },
  );
  testWidgets(
    'review retry closes after an earlier queue update and never navigates a dismissed sheet',
    (t) async {
      desktop(t);
      final f = AttendanceFake(),
          s = SessionController(f, clock: () => now),
          mock = MockEmasRepository(),
          c = PreviewController(mock, session: s);
      f.attendanceRows[row('submit')['id']] = row('submit');
      await t.pumpWidget(EmasCareApp(controller: c));
      await login(t, f, s, AppRole.coordinator);
      c.navigate(destination: Destination.activities);
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('attendance-review-tab')));
      Future<void> form() async {
        await tap(
          t,
          find.byKey(ValueKey('review-attendance-${row('submit')['id']}')),
        );
        await choose(t, 'attendance-review-method', 'I observed attendance');
        await t.enterText(
          find.byKey(const ValueKey('attendance-review-note')),
          'Observed demo fixture.',
        );
      }

      await form();
      f.attendanceMutation = (_, _, _) async =>
          throw const BackendFailure('unavailable');
      await tap(t, find.byKey(const ValueKey('save-attendance-review')));
      f.attendanceMutation = (_, _, _) async {
        f.attendanceRows[row('submit')['id']] = row('verify');
        f.emitAttendance();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return ActivityAttendance.fromJson(row('verify'));
      };
      await tap(t, find.widgetWithText(EmasButton, 'Try again').last);
      expect(find.byType(BottomSheet), findsNothing);
      f.attendanceRows[row('submit')['id']] = row('submit');
      f.emitAttendance();
      await t.pumpAndSettle();
      await form();
      final reply = Completer<ActivityAttendance>();
      f.attendanceMutation = (_, _, _) => reply.future;
      final save = find.byKey(const ValueKey('save-attendance-review'));
      final saveText = find
          .descendant(of: save, matching: find.byType(Text))
          .first;
      await Scrollable.ensureVisible(t.element(saveText), alignment: 0.5);
      await t.pumpAndSettle();
      await t.tap(saveText);
      await t.pump();
      expect(c.attendance!.busy('review:${row('submit')['id']}'), true);
      await Scrollable.ensureVisible(
        t.element(find.byTooltip('Close')),
        alignment: 0.5,
      );
      await t.pump();
      await t.tap(find.byTooltip('Close'));
      await t.pump();
      reply.complete(ActivityAttendance.fromJson(row('verify')));
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        find.byKey(const ValueKey('attendance-review-tab')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await dispose(t, c, s, mock, f);
    },
  );
  testWidgets(
    'permission loss clears the open coordinator review and its private draft',
    (t) async {
      desktop(t);
      final f = AttendanceFake(),
          s = SessionController(f, clock: () => now),
          mock = MockEmasRepository(),
          c = PreviewController(mock, session: s);
      f.attendanceRows[row('submit')['id']] = row('submit');
      await t.pumpWidget(EmasCareApp(controller: c));
      await login(t, f, s, AppRole.coordinator);
      c.navigate(destination: Destination.activities);
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('attendance-review-tab')));
      await tap(
        t,
        find.byKey(ValueKey('review-attendance-${row('submit')['id']}')),
      );
      await t.enterText(
        find.byKey(const ValueKey('attendance-review-note')),
        'Private draft that must disappear.',
      );
      f.attendanceEvents.addError(const BackendFailure('permission-denied'));
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Private draft that must disappear.'), findsNothing);
      expect(c.attendance!.records, isEmpty);
      expect(c.attendance!.actions, isEmpty);
      expect(c.attendance!.viewToken, isNull);
      await dispose(t, c, s, mock, f);
    },
  );
  testWidgets(
    'BM attendance history and review forms fit large text at phone, tablet and desktop widths',
    (t) async {
      for (final width in [320.0, 390.0, 768.0, 1440.0]) {
        t.view.physicalSize = Size(width, 1100);
        t.view.devicePixelRatio = 1;
        for (final role in [
          AppRole.elder,
          AppRole.family,
          AppRole.coordinator,
        ]) {
          final f = AttendanceFake(),
              s = SessionController(f, clock: () => now),
              mock = MockEmasRepository(),
              c = PreviewController(mock, session: s);
          f.attendanceRows[row('submit')['id']] = row('submit');
          await t.pumpWidget(EmasCareApp(controller: c));
          await login(t, f, s, role);
          c.toggleLanguage();
          c.setPreferences(text: true, motion: true, solid: true);
          c.navigate(destination: Destination.activities);
          await t.pumpAndSettle();
          if (role == AppRole.coordinator) {
            await tap(t, find.byKey(const ValueKey('attendance-review-tab')));
            await tap(
              t,
              find.byKey(ValueKey('review-attendance-${row('submit')['id']}')),
            );
            await choose(
              t,
              'attendance-review-method',
              'Saya menyemak senarai penganjur',
            );
            await t.enterText(
              find.byKey(const ValueKey('attendance-review-note')),
              'Nota semakan berdasarkan senarai kehadiran contoh.',
            );
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: 'review at $width');
            await tap(t, find.byTooltip('Tutup'));
          } else {
            await tap(t, find.byKey(const ValueKey('open-attendance-history')));
            expect(t.takeException(), isNull, reason: 'history at $width');
            f.attendanceRows[row('verify')['id']] = row('verify');
            f.emitAttendance();
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: 'verified at $width');
          }
          await dispose(t, c, s, mock, f);
        }
      }
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:emas_care/app/emas_app.dart';
import 'package:emas_care/app/preview_controller.dart';
import 'package:emas_care/app/session_controller.dart';
import 'package:emas_care/data/backend_failure.dart';
import 'package:emas_care/data/backend_repository.dart';
import 'package:emas_care/data/emas_repository.dart';
import 'package:emas_care/data/firebase_backend_repository.dart';
import 'package:emas_care/models/backend_models.dart';
import 'package:emas_care/models/preview_models.dart';

final fixture = jsonObject(
  jsonDecode(File('../docs/fixtures/stage2_checkins.json').readAsStringSync()),
);
Json response(String name) =>
    jsonObject(jsonObject(jsonObject(fixture[name])['response'])['data']);
ElderSettings settings({bool sharing = true, bool booking = true}) =>
    ElderSettings.fromJson({
      ...jsonObject(response('saveElderSettings')['settings']),
      'familySharingEnabled': sharing,
      'familyBookingEnabled': booking,
    });
CheckInRecord record() =>
    CheckInRecord.fromJson(jsonObject(response('submitCheckIn')['checkin']));
DailyStatus status() =>
    DailyStatus.fromJson(jsonObject(response('submitCheckIn')['dailyStatus']));
BackendProfile profile([
  AppRole role = AppRole.elder,
  String uid = 'elder_demo',
]) => BackendProfile.fromJson({
  'uid': uid,
  'displayName': 'Demo ${role.name}',
  'role': role.name,
  'townshipId': 'township_demo',
  'householdId': 'household_demo',
  'locale': 'en',
});
HouseholdAccess household(
  BackendProfile p, {
  bool sharing = true,
  bool booking = true,
  bool linked = true,
}) => HouseholdAccess.fromJson({
  'townshipId': p.townshipId,
  'memberUids': [p.uid],
  'familyUids': [p.uid],
  'elderIds': linked ? ['elder_demo'] : [],
  'elderAccess': {
    'elder_demo': {
      'displayName': 'Demo Elder',
      'familySharingEnabled': sharing,
      'familyBookingEnabled': booking,
    },
  },
}, p);

class FakeBackend implements BackendRepository {
  final auth = StreamController<String?>.broadcast(sync: true);
  final profiles = StreamController<BackendProfile?>.broadcast(sync: true);
  final settingsEvents = StreamController<ElderSettings?>.broadcast(sync: true);
  final checkinEvents = StreamController<List<CheckInRecord>>.broadcast(
    sync: true,
  );
  final householdEvents = StreamController<HouseholdAccess>.broadcast(
    sync: true,
  );
  late final StreamController<List<DailyStatus>> dailyEvents =
      StreamController.broadcast(
        sync: true,
        onCancel: () {
          dailyCancels++;
        },
      );
  final exceptionEvents = StreamController<List<CheckInRecord>>.broadcast(
    sync: true,
  );
  BackendProfile current = profile();
  Future<BackendProfile> Function()? context;
  Future<ElderSettings> Function(Json, String)? save;
  Future<(CheckInRecord, DailyStatus)> Function(String)? submit;
  final List<(Json, String)> saved = [];
  final List<String> keys = [], queries = [];
  int dailyCancels = 0;
  @override
  Stream<String?> authChanges() => auth.stream;
  @override
  Future<void> signIn(String email, String password) async {
    auth.add(current.uid);
    profiles.add(current);
  }

  @override
  Future<void> signOut() async {
    auth.add(null);
  }

  @override
  Stream<BackendProfile?> watchProfile(String uid) => profiles.stream;
  @override
  Future<BackendProfile> getBackendContext() =>
      context?.call() ?? Future.value(current);
  @override
  Stream<ElderSettings?> watchSettings(String uid) => settingsEvents.stream;
  @override
  Stream<List<CheckInRecord>> watchCheckIns(String uid) => checkinEvents.stream;
  @override
  Stream<HouseholdAccess> watchHousehold(BackendProfile profile) =>
      householdEvents.stream;
  @override
  Stream<List<DailyStatus>> watchDailyStatuses(
    String elderId,
    String householdId,
  ) {
    queries.add('$elderId/$householdId');
    return dailyEvents.stream;
  }

  @override
  Stream<List<CheckInRecord>> watchExceptions(String townshipId, String date) {
    queries.add('$townshipId/$date');
    return exceptionEvents.stream;
  }

  @override
  Future<ElderSettings> saveElderSettings(Json payload, String key) {
    saved.add((payload, key));
    return save?.call(payload, key) ?? Future.value(settings());
  }

  @override
  Future<(CheckInRecord, DailyStatus)> submitCheckIn(String key) {
    keys.add(key);
    return submit?.call(key) ?? Future.value((record(), status()));
  }

  @override
  Future<(CheckInRecord, DailyStatus)> recordPhoneResponse(
    String elderId,
    String key,
  ) async {
    keys.add(key);
    return (record(), status());
  }

  Future<void> close() async {
    await Future.wait([
      auth.close(),
      profiles.close(),
      settingsEvents.close(),
      checkinEvents.close(),
      householdEvents.close(),
      dailyEvents.close(),
      exceptionEvents.close(),
    ]);
  }
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
  late FakeBackend fake;
  late SessionController session;
  Future<void> login([AppRole role = AppRole.elder]) async {
    fake.current = profile(role);
    await session.signIn('forged-coordinator@emascare.test', 'demo');
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    fake = FakeBackend();
    session = SessionController(
      fake,
      clock: () => DateTime.utc(2026, 10, 21, 2),
    );
  });
  tearDown(() async {
    session.dispose();
    await fake.close();
  });

  test(
    'Stage 2 fixtures parse exact response envelopes and both timestamp formats',
    () {
      final result = FirebaseBackendRepository.unwrapEnvelope(
        jsonObject(fixture['submitCheckIn'])['response'],
      );
      expect(
        CheckInRecord.fromJson(jsonObject(result['checkin'])).source,
        'app',
      );
      expect(status().householdId, 'household_demo');
      expect(settings().dueLocalTime, '09:00');
      final iso = DateTime.utc(2026, 10, 21);
      expect(
        utcTimestamp(Timestamp.fromDate(iso)),
        utcTimestamp(iso.toIso8601String()),
      );
      expect(
        () => FirebaseBackendRepository.unwrapEnvelope({
          'contractVersion': 2,
          'data': {},
        }),
        throwsFormatException,
      );
    },
  );
  test('Malaysia date crosses UTC day and month boundary correctly', () {
    expect(malaysiaDate(DateTime.utc(2026, 10, 31, 16)), '2026-11-01');
    expect(malaysiaDate(DateTime.utc(2026, 10, 31, 15, 59)), '2026-10-31');
    expect(malaysiaTime(DateTime.utc(2026, 10, 21, 1, 5)), '09:05');
  });
  test('stable Functions details.reason is preserved and localized', () {
    final failure = BackendFailure.from(
      FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Variable text',
        details: {'reason': 'CHECKIN_PAUSED'},
      ),
    );
    expect(failure.reason, 'CHECKIN_PAUSED');
    expect(failure.message(false), contains('Unpause'));
    expect(failure.message(true), contains('Nyahjeda'));
  });
  test('server role overrides email and URL role selection', () async {
    final mock = MockEmasRepository();
    final controller = PreviewController(mock, session: session);
    await login();
    controller.restore(
      const AppLocation(AppRole.coordinator, Destination.today),
    );
    controller.navigate(role: AppRole.family);
    expect(controller.role, AppRole.elder);
    controller.dispose();
    mock.dispose();
  });
  test('missing or mismatched server profile fails closed', () async {
    fake.context = () async => profile(AppRole.coordinator);
    await login();
    expect(session.profile, isNull);
    expect(session.authError?.code, 'permission-denied');
    expect(session.checkins, isEmpty);
  });
  test(
    'late context completion cannot restore private data after sign-out',
    () async {
      final pending = Completer<BackendProfile>();
      fake.context = () => pending.future;
      await login();
      await session.signOut();
      pending.complete(profile());
      await Future<void>.delayed(Duration.zero);
      expect(session.profile, isNull);
      expect(session.checkins, isEmpty);
    },
  );
  test(
    'duplicate taps are ignored and retries retain a key; new action gets a new key',
    () async {
      await login();
      final pending = Completer<(CheckInRecord, DailyStatus)>();
      fake.submit = (_) => pending.future;
      final first = session.checkIn();
      await session.checkIn();
      expect(fake.keys.length, 1);
      pending.completeError(const BackendFailure('unavailable'));
      await first;
      final original = fake.keys.single;
      fake.submit = (_) async => (record(), status());
      await session.checkIn();
      expect(fake.keys.last, original);
      await session.checkIn();
      expect(fake.keys.last, isNot(original));
    },
  );
  test(
    'settings retry retains frozen business fields and does not replace newer stream state',
    () async {
      await login();
      fake.settingsEvents.add(settings(sharing: false));
      fake.save = (_, key) async => throw const BackendFailure('unavailable');
      await session.saveSettings({
        'familySharingEnabled': true,
        'familyBookingEnabled': false,
      });
      final key = fake.saved.single.$2;
      fake.save = (_, key) async => settings(sharing: true);
      await session.saveSettings({'familySharingEnabled': false});
      expect(fake.saved.last.$1, {
        'familySharingEnabled': true,
        'familyBookingEnabled': false,
      });
      expect(fake.saved.last.$2, key);
      expect(session.settings?.sharing, false);
    },
  );
  test(
    'family sharing withdrawal immediately clears status and cancels subscription',
    () async {
      await login(AppRole.family);
      fake.householdEvents.add(household(fake.current));
      fake.dailyEvents.add([status()]);
      expect(session.todayStatus?.state, CheckInState.ok);
      expect(fake.queries, ['elder_demo/household_demo']);
      fake.householdEvents.add(household(fake.current, sharing: false));
      expect(session.statuses, isEmpty);
      expect(fake.dailyCancels, 1);
      fake.dailyEvents.add([status()]);
      expect(session.statuses, isEmpty);
      expect(session.selectedElder?.booking, true);
    },
  );
  test(
    'booking consent does not gate sharing and cannot grant sharing',
    () async {
      await login(AppRole.family);
      fake.householdEvents.add(household(fake.current, booking: false));
      fake.dailyEvents.add([status()]);
      expect(session.todayStatus?.state, CheckInState.ok);
      fake.householdEvents.add(
        household(fake.current, sharing: false, booking: true),
      );
      expect(session.todayStatus, isNull);
      expect(fake.queries.length, 1);
    },
  );
  test(
    'permission-denied clears family data and requires a permission recheck',
    () async {
      await login(AppRole.family);
      fake.householdEvents.add(household(fake.current));
      fake.dailyEvents.add([status()]);
      fake.dailyEvents.addError(const BackendFailure('permission-denied'));
      expect(session.todayStatus, isNull);
      expect(session.familyError?.code, 'permission-denied');
      expect(fake.dailyCancels, 1);
    },
  );
  test(
    'unlinked account never subscribes to another household elder',
    () async {
      await login(AppRole.family);
      fake.householdEvents.add(household(fake.current, linked: false));
      expect(fake.queries, isEmpty);
      expect(session.todayStatus, isNull);
    },
  );
  test(
    'empty elder query is not a successful check-in; coordinator query uses MY date',
    () async {
      await login();
      fake.checkinEvents.add([]);
      expect(session.todayCheckIn, isNull);
      await session.signOut();
      await login(AppRole.coordinator);
      expect(fake.queries.single, 'township_demo/2026-10-21');
    },
  );

  testWidgets(
    'live BM and large text layouts fit phone and desktop for every role',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final mock = MockEmasRepository();
      final controller = PreviewController(mock, session: session);
      await tester.pumpWidget(EmasCareApp(controller: controller));
      for (final role in AppRole.values) {
        await tester.runAsync(() => login(role));
        await tester.pump();
        fake.settingsEvents.add(settings());
        fake.checkinEvents.add([record()]);
        fake.householdEvents.add(household(fake.current));
        fake.dailyEvents.add([status()]);
        fake.exceptionEvents.add([record()]);
        expect(session.profile?.role, role);
        expect(
          session.dataLoading,
          false,
          reason: 'Domain fixtures ready for ${role.name}',
        );
        controller.malay = true;
        controller.setPreferences(text: true);
        for (final width in [320.0, 390.0, 768.0, 1440.0]) {
          tester.view.physicalSize = Size(width, 1100);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '${role.name}/$width');
          expect(find.byKey(const ValueKey('role-selector')), findsNothing);
        }
        await session.signOut();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      mock.dispose();
    },
  );
  testWidgets(
    'family screen removes previously displayed success on withdrawal',
    (tester) async {
      final mock = MockEmasRepository();
      final controller = PreviewController(mock, session: session);
      await tester.pumpWidget(EmasCareApp(controller: controller));
      await tester.runAsync(() => login(AppRole.family));
      await tester.pump();
      fake.householdEvents.add(household(fake.current));
      fake.dailyEvents.add([status()]);
      expect(session.profile?.role, AppRole.family);
      expect(session.dataLoading, false);
      await tester.pumpAndSettle();
      expect(find.text('Saya OK received'), findsOneWidget);
      fake.householdEvents.add(household(fake.current, sharing: false));
      await tester.pumpAndSettle();
      expect(find.text('Saya OK received'), findsNothing);
      expect(find.byKey(const ValueKey('family-private')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      mock.dispose();
    },
  );
}

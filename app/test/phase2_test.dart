import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:emas_care/app/community_controller.dart';
import 'package:emas_care/app/companion_demo_controller.dart';
import 'package:emas_care/app/emas_app.dart';
import 'package:emas_care/app/preview_controller.dart';
import 'package:emas_care/app/session_controller.dart';
import 'package:emas_care/data/backend_failure.dart';
import 'package:emas_care/data/community_repository.dart';
import 'package:emas_care/data/emas_repository.dart';
import 'package:emas_care/data/phase2_samples.dart';
import 'package:emas_care/models/backend_models.dart';
import 'package:emas_care/models/community_models.dart';
import 'package:emas_care/models/companion_ui_models.dart';
import 'package:emas_care/models/preview_models.dart';
import 'package:emas_care/shared/design_system.dart';
import 'backend_test.dart' as stage2;

final now = DateTime.utc(2026, 10, 21, 2);
CompanionDraft draft(String intent, {int hour = 10}) => CompanionDraft(
  intentId: intent,
  elderName: 'Mr Tan',
  title: 'Sample walk',
  task: CompanionTask.walkWithMe,
  startsAt: DateTime.parse(
    '2026-10-22T${hour.toString().padLeft(2, '0')}:00:00+08:00',
  ),
  minutes: 60,
  language: 'en',
  placeName: 'Community hall',
);

class CommunityFake extends stage2.FakeBackend implements CommunityRepository {
  final activityEvents = StreamController<List<ActivityRecord>>.broadcast(
    sync: true,
  );
  final placeEvents = StreamController<List<PlaceRecord>>.broadcast(sync: true);
  final pairingEvents = StreamController<List<PairingRecord>>.broadcast(
    sync: true,
  );
  final helperEvents = StreamController<HelperProfileRecord?>.broadcast(
    sync: true,
  );
  final List<String> readScopes = [];
  @override
  Stream<List<ActivityRecord>> watchActivities(String townshipId) {
    readScopes.add('activities:$townshipId');
    return activityEvents.stream;
  }

  @override
  Stream<List<PlaceRecord>> watchPlaces(String townshipId) {
    readScopes.add('places:$townshipId');
    return placeEvents.stream;
  }

  @override
  Stream<List<PairingRecord>> watchPairings(BackendProfile profile) {
    if (profile.role == AppRole.family) {
      throw StateError('Family cannot read pairings.');
    }
    readScopes.add(
      'pairings:${profile.role.name}:${profile.role == AppRole.coordinator ? profile.townshipId : profile.uid}',
    );
    return pairingEvents.stream;
  }

  @override
  Stream<HelperProfileRecord?> watchHelperProfile(String uid) {
    readScopes.add('helper:$uid');
    return helperEvents.stream;
  }

  @override
  Future<void> close() async {
    await super.close();
    await Future.wait([
      activityEvents.close(),
      placeEvents.close(),
      pairingEvents.close(),
      helperEvents.close(),
    ]);
  }

  void emitCatalog() {
    activityEvents.add(sampleActivities(now));
    placeEvents.add(samplePlaces(now));
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
  test(
    'sample requests deduplicate one intent while new intentions stay distinct',
    () {
      final demo = CompanionDemoController();
      final first = demo.create(AppRole.elder, draft('same'));
      expect(demo.create(AppRole.elder, draft('same')), same(first));
      expect(demo.requests.length, 1);
      demo.create(AppRole.elder, draft('new'));
      expect(demo.requests.length, 2);
      demo.dispose();
    },
  );
  test('family booking requires elder consent and family cannot grant it', () {
    final demo = CompanionDemoController();
    demo.setFamilyBooking(AppRole.elder, false);
    expect(
      () => demo.create(AppRole.family, draft('no-consent')),
      throwsStateError,
    );
    expect(() => demo.setFamilyBooking(AppRole.family, true), throwsStateError);
    expect(
      () => demo.create(AppRole.helper, draft('helper')),
      throwsStateError,
    );
    demo.setFamilyBooking(AppRole.elder, true);
    expect(
      demo.create(AppRole.family, draft('allowed')).requestedBy,
      AppRole.family,
    );
    demo.dispose();
  });
  test(
    'only coordinator can assign the available paired sample helper within sample hours',
    () {
      final demo = CompanionDemoController();
      final request = demo.create(AppRole.elder, draft('a'));
      expect(() => demo.assign(AppRole.elder, request), throwsStateError);
      demo.setHelperAvailable(false);
      expect(demo.canAssign(request), false);
      expect(() => demo.assign(AppRole.coordinator, request), throwsStateError);
      demo.setHelperAvailable(true);
      final late = demo.create(AppRole.elder, draft('late', hour: 18));
      expect(demo.canAssign(late), false);
      demo.assign(AppRole.coordinator, request);
      expect(request.stage, DemoSessionStage.assigned);
      demo.dispose();
    },
  );
  test(
    'helper must accept then start then finish; no participant can skip completion steps',
    () {
      final demo = CompanionDemoController();
      final r = demo.create(AppRole.elder, draft('sequence'));
      expect(() => demo.start(AppRole.helper, r), throwsStateError);
      expect(() => demo.confirm(AppRole.elder, r), throwsStateError);
      demo.assign(AppRole.coordinator, r);
      expect(() => demo.accept(AppRole.family, r), throwsStateError);
      demo.accept(AppRole.helper, r);
      expect(() => demo.finish(AppRole.helper, r), throwsStateError);
      demo.start(AppRole.helper, r);
      demo.finish(AppRole.helper, r);
      expect(r.stage, DemoSessionStage.awaitingConfirmation);
      demo.dispose();
    },
  );
  test(
    'two distinct participants must confirm; retries and family confirmations cannot complete a session',
    () {
      final demo = CompanionDemoController();
      final r = demo.create(AppRole.elder, draft('confirm'));
      demo.assign(AppRole.coordinator, r);
      demo.accept(AppRole.helper, r);
      demo.start(AppRole.helper, r);
      demo.finish(AppRole.helper, r);
      demo.confirm(AppRole.helper, r);
      demo.confirm(AppRole.helper, r);
      expect(r.stage, DemoSessionStage.awaitingConfirmation);
      expect(() => demo.confirm(AppRole.family, r), throwsStateError);
      expect(() => demo.confirm(AppRole.coordinator, r), throwsStateError);
      demo.confirm(AppRole.elder, r);
      expect(r.stage, DemoSessionStage.completed);
      expect(() => demo.start(AppRole.helper, r), throwsStateError);
      demo.dispose();
    },
  );
  test(
    'cancelled requests cannot be assigned, finished or confirmed; reset clears sample state',
    () {
      final demo = CompanionDemoController();
      final r = demo.create(AppRole.elder, draft('cancel'));
      demo.cancel(AppRole.elder, r);
      expect(() => demo.assign(AppRole.coordinator, r), throwsStateError);
      expect(() => demo.finish(AppRole.helper, r), throwsStateError);
      expect(() => demo.confirm(AppRole.elder, r), throwsStateError);
      demo.reset();
      expect(demo.requests, isEmpty);
      expect(demo.familyBooking, true);
      demo.dispose();
    },
  );
  test(
    'access notices expire at their exact boundary and only approved HTTPS Maps URLs open',
    () {
      final p = samplePlaces(now)[1];
      expect(p.notice!.activeAt(now.add(const Duration(hours: 3))), true);
      expect(p.notice!.activeAt(now.add(const Duration(hours: 4))), false);
      expect(p.mapsLink?.host, 'maps.google.com');
      final unknown = PlaceRecord.fromJson({
        'id': 'unknown',
        'townshipId': 't',
        'name': 'Unrecorded',
        'mapsUrl': 'javascript:alert(1)',
      });
      expect(unknown.stepFree, isNull);
      expect(unknown.toilet, isNull);
      expect(unknown.mapsLink, isNull);
      final other = PlaceRecord.fromJson({
        'id': 'other',
        'townshipId': 't',
        'name': 'Other',
        'mapsUrl': 'https://example.com/maps',
      });
      expect(other.mapsLink, isNull);
      expect(activityDate(DateTime.utc(2026, 10, 31, 16), true), 'Ahd, 1 Nov');
    },
  );

  for (final role in AppRole.values) {
    test(
      'community read scope for ${role.name} follows the authenticated profile',
      () async {
        final fake = CommunityFake()
          ..current = stage2.profile(role, '${role.name}_demo');
        final session = SessionController(fake, clock: () => now);
        final community = CommunityController(session, fake);
        await session.signIn('irrelevant@test', 'demo');
        await Future<void>.delayed(Duration.zero);
        fake.emitCatalog();
        expect(
          fake.readScopes,
          containsAll(['activities:township_demo', 'places:township_demo']),
        );
        expect(community.activities.length, 3);
        if (role == AppRole.family) {
          expect(
            fake.readScopes.where(
              (s) => s.startsWith('pairings:') || s.startsWith('helper:'),
            ),
            isEmpty,
          );
        }
        if (role == AppRole.helper) {
          expect(fake.readScopes, contains('helper:helper_demo'));
        }
        if (role == AppRole.coordinator) {
          expect(
            fake.readScopes,
            contains('pairings:coordinator:township_demo'),
          );
        }
        community.dispose();
        session.dispose();
        await fake.close();
      },
    );
  }
  test(
    'community records clear and stale events are ignored after permission denial or sign-out',
    () async {
      final fake = CommunityFake();
      final session = SessionController(fake, clock: () => now);
      final community = CommunityController(session, fake);
      await session.signIn('elder@test', 'demo');
      await Future<void>.delayed(Duration.zero);
      fake.emitCatalog();
      expect(community.activities, isNotEmpty);
      fake.pairingEvents.addError(const BackendFailure('permission-denied'));
      expect(community.activities, isEmpty);
      expect(community.catalogError?.code, 'permission-denied');
      fake.emitCatalog();
      expect(community.activities, isEmpty);
      community.retry();
      fake.emitCatalog();
      expect(community.activities, isNotEmpty);
      await session.signOut();
      expect(community.activities, isEmpty);
      expect(community.places, isEmpty);
      fake.emitCatalog();
      expect(community.activities, isEmpty);
      community.dispose();
      session.dispose();
      await fake.close();
    },
  );

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    final target = tester.widget(finder) is EmasButton
        ? find.descendant(of: finder, matching: find.byType(Text)).first
        : finder;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'expired access notice stays visible and needs review without navigation',
    (tester) async {
      var clockNow = now;
      final fake = CommunityFake();
      final session = SessionController(fake, clock: () => clockNow);
      final mock = MockEmasRepository();
      final c = PreviewController(mock, session: session);
      await tester.pumpWidget(EmasCareApp(controller: c));
      await tester.runAsync(() async {
        await session.signIn('elder@test', 'demo');
        await Future<void>.delayed(Duration.zero);
      });
      fake.activityEvents.add(sampleActivities(now));
      fake.placeEvents.add([
        PlaceRecord.fromJson({
          'id': 'sample_garden',
          'townshipId': 'township_demo',
          'name': 'Sample garden',
          'liveStatus': {
            'level': 'caution',
            'text': 'Notice expires in five seconds',
            'expiresAt': now.add(const Duration(seconds: 5)).toIso8601String(),
          },
        }),
      ]);
      c.navigate(destination: Destination.activities);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const ValueKey('activity-garden')));
      expect(find.text('Notice expires in five seconds'), findsOneWidget);
      clockNow = now.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Notice expires in five seconds'), findsOneWidget);
      expect(find.text('Needs coordinator review'), findsWidgets);
      expect(
        find.textContaining('Expiry does not mean the place is safe'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      session.dispose();
      mock.dispose();
      await fake.close();
    },
  );

  testWidgets(
    'complete sample request crosses roles and requires separate confirmations',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final mock = MockEmasRepository();
      final c = PreviewController(mock);
      await tester.pumpWidget(EmasCareApp(controller: c));
      c.navigate(destination: Destination.activities);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const ValueKey('activity-tai_chi')));
      await tapVisible(tester, find.text('Request a companion'));
      await tapVisible(tester, find.byKey(const ValueKey('review-request')));
      expect(find.text('Not sent'), findsNothing);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('create-sample-request')),
      );
      expect(c.demo.requests.length, 1);
      c.navigate(
        role: AppRole.coordinator,
        destination: Destination.activities,
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Choose companion'));
      await tapVisible(tester, find.text('Assign sample companion'));
      c.navigate(role: AppRole.helper, destination: Destination.companion);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Accept session'));
      await tapVisible(tester, find.text('Start session'));
      await tapVisible(tester, find.text('Finish session'));
      await tapVisible(tester, find.text('Confirm my participation'));
      expect(
        c.demo.requests.single.stage,
        DemoSessionStage.awaitingConfirmation,
      );
      c.navigate(role: AppRole.family, destination: Destination.companion);
      await tester.pumpAndSettle();
      expect(find.text('Confirm my participation'), findsNothing);
      c.navigate(role: AppRole.elder, destination: Destination.companion);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Confirm my participation'));
      expect(c.demo.requests.single.stage, DemoSessionStage.completed);
      expect(find.text('Confirmed by both'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      mock.dispose();
    },
  );

  testWidgets(
    'family request form and sample request list disappear when elder withdraws booking',
    (tester) async {
      final mock = MockEmasRepository();
      final c = PreviewController(mock);
      c.demo.create(AppRole.elder, draft('family-visibility'));
      await tester.pumpWidget(EmasCareApp(controller: c));
      c.navigate(role: AppRole.family, destination: Destination.companion);
      await tester.pumpAndSettle();
      expect(find.text('Sample walk'), findsOneWidget);
      c.demo.setFamilyBooking(AppRole.elder, false);
      await tester.pumpAndSettle();
      expect(find.text('Sample walk'), findsNothing);
      expect(find.text('Booking permission is off.'), findsOneWidget);
      expect(
        tester
            .widget<EmasButton>(
              find.widgetWithText(EmasButton, 'New sample request'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      mock.dispose();
    },
  );

  testWidgets(
    'connected form stays a draft, reacts to consent withdrawal and clears on sign-out',
    (tester) async {
      final fake = CommunityFake()
        ..current = stage2.profile(AppRole.family, 'family_demo');
      final session = SessionController(fake, clock: () => now);
      final mock = MockEmasRepository();
      final c = PreviewController(mock, session: session);
      await tester.pumpWidget(EmasCareApp(controller: c));
      await tester.runAsync(() async {
        await session.signIn('family@test', 'demo');
        await Future<void>.delayed(Duration.zero);
      });
      fake.householdEvents.add(
        stage2.household(fake.current, sharing: false, booking: true),
      );
      fake.emitCatalog();
      c.navigate(destination: Destination.activities);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const ValueKey('activity-tai_chi')));
      await tapVisible(tester, find.text('Preview a companion request'));
      await tapVisible(tester, find.byKey(const ValueKey('review-request')));
      expect(find.text('Not sent'), findsOneWidget);
      expect(find.byKey(const ValueKey('create-sample-request')), findsNothing);
      expect(c.demo.requests, isEmpty);
      fake.householdEvents.add(stage2.household(fake.current, booking: false));
      await tester.pumpAndSettle();
      expect(find.text('Does this look right?'), findsNothing);
      expect(find.text('Booking needs your elder’s consent.'), findsNothing);
      expect(find.byTooltip('Close'), findsNothing);
      await session.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Booking needs your elder’s consent.'), findsNothing);
      expect(c.community!.activities, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      session.dispose();
      mock.dispose();
      await fake.close();
    },
  );

  testWidgets(
    'request and review sheets fit BM/larger text at phone and desktop widths',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final mock = MockEmasRepository();
      final c = PreviewController(mock);
      c.malay = true;
      c.setPreferences(text: true, motion: true, solid: true);
      await tester.pumpWidget(EmasCareApp(controller: c));
      c.navigate(destination: Destination.activities);
      for (final width in [320.0, 390.0, 768.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 1100);
        await tester.pumpAndSettle();
        await tapVisible(tester, find.byKey(const ValueKey('activity-garden')));
        await tapVisible(
          tester,
          find.widgetWithText(EmasButton, 'Minta teman'),
        );
        await tapVisible(tester, find.byKey(const ValueKey('review-request')));
        expect(tester.takeException(), isNull, reason: 'review at $width');
        await tapVisible(tester, find.byTooltip('Tutup'));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      mock.dispose();
    },
  );

  testWidgets(
    'awaiting and completed sample sessions fit every role in BM with larger text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final mock = MockEmasRepository();
      final c = PreviewController(mock);
      final r = c.demo.create(AppRole.elder, draft('responsive-session'));
      c.demo.assign(AppRole.coordinator, r);
      c.demo.accept(AppRole.helper, r);
      c.demo.start(AppRole.helper, r);
      c.demo.finish(AppRole.helper, r);
      await tester.pumpWidget(EmasCareApp(controller: c));
      c.malay = true;
      c.setPreferences(text: true, motion: true, solid: true);
      for (final complete in [false, true]) {
        if (complete) {
          c.demo.confirm(AppRole.helper, r);
          c.demo.confirm(AppRole.elder, r);
        }
        for (final role in AppRole.values) {
          c.navigate(
            role: role,
            destination: role == AppRole.coordinator
                ? Destination.activities
                : Destination.companion,
          );
          for (final width in [320.0, 390.0, 768.0, 1440.0]) {
            tester.view.physicalSize = Size(width, 1100);
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '${role.name}/$width/completed=$complete',
            );
          }
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      mock.dispose();
    },
  );
}

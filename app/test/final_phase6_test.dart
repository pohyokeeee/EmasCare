import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:emas_care/app/emas_app.dart';
import 'package:emas_care/app/preview_controller.dart';
import 'package:emas_care/app/session_controller.dart';
import 'package:emas_care/data/emas_repository.dart';
import 'package:emas_care/models/preview_models.dart';
import 'package:emas_care/features/coordination/coordination_view.dart';
import 'package:emas_care/features/coordination/coordination_review.dart';
import 'package:emas_care/shared/design_system.dart';
import 'stage3_test.dart' as sessions;
import 'stage6_test.dart' as coordination;

class Harness {
  final f = coordination.CoordinationFake();
  late final s = SessionController(f, clock: () => DateTime.utc(2026, 10, 22));
  final mock = MockEmasRepository();
  late final c = PreviewController(mock, session: s);
  Future<void> mount(WidgetTester t, AppRole role) async {
    await t.pumpWidget(EmasCareApp(controller: c));
    await t.runAsync(() => coordination.sign(f, s, role));
    f.emitCommunity();
    f.emitCoord();
    await t.pumpAndSettle();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    c.dispose();
    s.dispose();
    mock.dispose();
    await f.close();
  }
}

Future<void> tap(WidgetTester t, Finder finder) async {
  final target = t.widget(finder) is EmasButton
      ? find.descendant(of: finder, matching: find.byType(Text)).first
      : finder;
  await Scrollable.ensureVisible(t.element(target), alignment: .5);
  await t.pumpAndSettle();
  await t.tap(target);
  await t.pumpAndSettle();
}

void size(WidgetTester t, double width) {
  t.view.physicalSize = Size(width, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<void> openForm(WidgetTester t, String kind) async {
  openCoordinationForm(
    t.element(find.byKey(const ValueKey('stage6-reports'))),
    kind,
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('blocking review retains an exact companion reference without a request display projection', (t) async {
    size(t, 1440);
    final h = Harness();
    try {
      await h.mount(t, AppRole.coordinator);
      await openForm(t, 'blockHelper');
      await t.enterText(find.descendant(of: find.byType(CoordinationForm), matching: find.byType(TextField)).last, 'Review without an available name.');
      await tap(t, find.widgetWithText(EmasButton, 'Review details'));
      expect(find.text('Companion reference: helper_demo'), findsOneWidget);
      expect(h.f.coordCalls.where((e) => e.$1 == 'blockHelper'), isEmpty);
    } finally {
      await h.close(t);
    }
  });
  setUpAll(() async {
    final fonts = FontLoader('Manrope');
    for (final weight in [400, 500, 600, 700]) {
      fonts.addFont(rootBundle.load('assets/fonts/Manrope-$weight.ttf'));
    }
    await fonts.load();
  });
  testWidgets(
    'warning review identifies place, action and MYT deadline before any write; clear identifies same place',
    (t) async {
      size(t, 1440);
      final h = Harness();
      try {
        await h.mount(t, AppRole.coordinator);
        await openForm(t, 'setPlaceWarning');
        await t.enterText(
          find
              .descendant(
                of: find.byType(CoordinationForm),
                matching: find.byType(TextField),
              )
              .last,
          'Wet path: use the hall entrance.',
        );
        await tap(t, find.widgetWithText(EmasButton, 'Review details'));
        final card = find.byKey(const ValueKey('coordination-review-details'));
        expect(
          find.descendant(of: card, matching: find.text('Community Garden')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text('Record a warning')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.textContaining('10:00 MYT')),
          findsOneWidget,
        );
        expect(h.f.coordCalls.where((e) => e.$1 == 'setPlaceWarning'), isEmpty);
        await tap(t, find.text('Edit details'));
        await tap(t, find.text('Explicitly clear this warning'));
        expect(
          find.descendant(of: card, matching: find.text('Community Garden')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text('Clear recorded warning'),
          ),
          findsOneWidget,
        );
        expect(h.f.coordCalls.where((e) => e.$1 == 'setPlaceWarning'), isEmpty);
        await tap(t, find.byKey(const ValueKey('confirm-coordination-action')));
        final call = h.f.coordCalls
            .where((e) => e.$1 == 'setPlaceWarning')
            .single;
        expect(call.$2, {'placeId': 'place_garden', 'warning': null});
        expect(call.$3, isNotEmpty);
      } finally {
        await h.close(t);
      }
    },
  );
  testWidgets(
    'blocking review identifies both participants and keeps the selected pair on confirmed write',
    (t) async {
      size(t, 1440);
      final h = Harness();
      h.f.rows['review-session'] = {
        ...sessions.result('assign'),
        'id': 'review-session',
        'elderDisplayName': 'Demo Elder',
        'helperDisplay': {'displayName': 'Demo Helper', 'tier': 'T3'},
      };
      try {
        await h.mount(t, AppRole.elder);
        await openForm(t, 'blockHelper');
        await t.enterText(
          find
              .descendant(
                of: find.byType(CoordinationForm),
                matching: find.byType(TextField),
              )
              .last,
          'Please arrange a different companion.',
        );
        await tap(t, find.widgetWithText(EmasButton, 'Review details'));
        final card = find.byKey(const ValueKey('coordination-review-details'));
        expect(
          find.descendant(
            of: card,
            matching: find.text(h.s.profile!.displayName),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text('Demo Helper')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Existing bookings are not cancelled'),
          findsOneWidget,
        );
        expect(h.f.coordCalls.where((e) => e.$1 == 'blockHelper'), isEmpty);
        await tap(t, find.byKey(const ValueKey('confirm-coordination-action')));
        final call = h.f.coordCalls.where((e) => e.$1 == 'blockHelper').single;
        expect(call.$2['elderId'], 'elder_demo');
        expect(call.$2['helperId'], 'helper_demo');
      } finally {
        await h.close(t);
      }
    },
  );
  testWidgets(
    'pending due processing disables duplicate activation and announces work until the saved result returns',
    (t) async {
      size(t, 1440);
      final h = Harness();
      final response = Completer<Map<String, dynamic>>();
      try {
        await h.mount(t, AppRole.coordinator);
        await tap(t, find.byKey(const ValueKey('stage6-operations')));
        h.f.command = (name, fields, key) => name == 'processDemoDueItems'
            ? response.future
            : Future.value(coordination.result(name));
        final button = find.byKey(const ValueKey('process-due-items'));
        await Scrollable.ensureVisible(t.element(button), alignment: .5);
        await t.pumpAndSettle();
        final buttonText = find
            .descendant(of: button, matching: find.byType(Text))
            .first;
        await Scrollable.ensureVisible(t.element(buttonText), alignment: .5);
        await t.pumpAndSettle();
        await t.tap(buttonText);
        await t.pump();
        expect(t.widget<EmasButton>(button).onPressed, isNull);
        expect(find.text('Processing check-ins…'), findsOneWidget);
        final pendingText = find.text('Processing check-ins…');
        await Scrollable.ensureVisible(t.element(pendingText), alignment: .5);
        await t.pump(const Duration(milliseconds: 100));
        await t.tapAt(t.getCenter(pendingText));
        await t.pump();
        expect(
          h.f.coordCalls.where((e) => e.$1 == 'processDemoDueItems').length,
          1,
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
          findsWidgets,
        );
        h.f.command = null;
        response.complete({
          'processedAt': '2026-10-22T00:00:00Z',
          'remindersCreated': 1,
          'missedAlertsCreated': 2,
          'warningsCleared': 0,
        });
        await t.pump();
        h.f.emitCommunity();
        h.f.emitCoord();
        await t.pumpAndSettle();
        expect(
          find.textContaining('1 reminders and 2 missed notices'),
          findsOneWidget,
        );
      } finally {
        if (!response.isCompleted) response.complete({});
        await h.close(t);
      }
    },
  );
  testWidgets(
    'report review disables both state changes while the confirmed action is pending',
    (t) async {
      size(t, 1440);
      final h = Harness();
      final response = Completer<Map<String, dynamic>>();
      h.f.reportsData.add({
        ...coordination.result('submitReport')['report']
            as Map<String, dynamic>,
        'state': 'new',
      });
      try {
        await h.mount(t, AppRole.coordinator);
        await tap(t, find.byKey(const ValueKey('stage6-reports')));
        h.f.command = (name, fields, key) => name == 'reviewReport'
            ? response.future
            : Future.value(coordination.result(name));
        final seen = find.widgetWithText(OutlinedButton, 'Mark seen');
        await Scrollable.ensureVisible(t.element(seen), alignment: .5);
        await t.pumpAndSettle();
        await t.tap(seen);
        await t.pump();
        expect(t.widget<OutlinedButton>(seen).onPressed, isNull);
        expect(
          t
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Mark done'),
              )
              .onPressed,
          isNull,
        );
        expect(h.f.coordCalls.where((e) => e.$1 == 'reviewReport').length, 1);
        h.f.command = null;
        h.f.reportsData[0] = {...h.f.reportsData[0], 'state': 'seen'};
        h.f.emitCoord();
        response.complete(coordination.result('reviewReport'));
        await t.pumpAndSettle();
        expect(find.text('Seen'), findsOneWidget);
        expect(find.text('Mark seen'), findsNothing);
      } finally {
        if (!response.isCompleted) response.complete({});
        await h.close(t);
      }
    },
  );
  testWidgets(
    'family cheer gives immediate pending feedback and returns to saved once-only state',
    (t) async {
      size(t, 1440);
      final h = Harness();
      final response = Completer<Map<String, dynamic>>();
      try {
        await h.mount(t, AppRole.family);
        await tap(t, find.byKey(const ValueKey('stage6-progress')));
        h.f.command = (name, fields, key) => name == 'sendFamilyCheer'
            ? response.future
            : Future.value(coordination.result(name));
        final button = find.byKey(const ValueKey('family-cheer'));
        final label = find
            .descendant(of: button, matching: find.byType(Text))
            .first;
        await Scrollable.ensureVisible(t.element(label), alignment: .5);
        await t.pumpAndSettle();
        await t.tap(label);
        await t.pump();
        expect(t.widget<EmasButton>(button).onPressed, isNull);
        expect(find.text('Sending cheer…'), findsOneWidget);
        expect(
          h.f.coordCalls.where((e) => e.$1 == 'sendFamilyCheer').length,
          1,
        );
        final pid = h.f.coordCalls
            .lastWhere((e) => e.$1 == 'sendFamilyCheer')
            .$2['participationId'];
        h.f.command = null;
        h.f.cheersData.add({
          ...coordination.result('sendFamilyCheer')['cheer']
              as Map<String, dynamic>,
          'participationId': pid,
          'familyUid': 'family_demo',
        });
        h.f.emitCoord();
        response.complete(coordination.result('sendFamilyCheer'));
        await t.pumpAndSettle();
        expect(find.text('Cheer sent'), findsOneWidget);
        expect(t.widget<EmasButton>(button).onPressed, isNull);
      } finally {
        if (!response.isCompleted) response.complete({});
        await h.close(t);
      }
    },
  );
  testWidgets(
    'connected coordinator navigation says Tools and Alat while the design preview keeps People',
    (t) async {
      size(t, 1440);
      final h = Harness();
      try {
        await h.mount(t, AppRole.coordinator);
        expect(h.c.navName(Destination.rewards), 'Tools');
        expect(find.text('Tools'), findsOneWidget);
        h.c.toggleLanguage();
        await t.pumpAndSettle();
        expect(find.text('Alat'), findsOneWidget);
        final preview = PreviewController(h.mock);
        preview.navigate(role: AppRole.coordinator);
        expect(preview.navName(Destination.rewards), 'People');
        preview.dispose();
      } finally {
        await h.close(t);
      }
    },
  );
  testWidgets(
    'confirmation context fits phone/tablet/desktop with BM, larger text and reduced motion',
    (t) async {
      for (final width in [320.0, 390.0, 768.0, 1440.0]) {
        t.view.physicalSize = Size(width, 1100);
        t.view.devicePixelRatio = 1;
        final h = Harness();
        try {
          await h.mount(t, AppRole.coordinator);
          h.c.toggleLanguage();
          h.c.setPreferences(text: true, motion: true, solid: true);
          await t.pumpAndSettle();
          await openForm(t, 'setPlaceWarning');
          await t.enterText(
            find
                .descendant(
                  of: find.byType(CoordinationForm),
                  matching: find.byType(TextField),
                )
                .last,
            'Laluan basah; semakan diperlukan.',
          );
          await tap(t, find.widgetWithText(EmasButton, 'Semak butiran'));
          expect(find.byType(CoordinationReview), findsOneWidget);
          expect(find.text('Semakan perlu'), findsOneWidget);
          await tap(t, find.text('Edit butiran'));
          expect(t.takeException(), isNull, reason: '$width');
        } finally {
          await h.close(t);
        }
      }
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
}

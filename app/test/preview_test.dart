import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:emas_care/app/emas_app.dart';
import 'package:emas_care/app/preview_controller.dart';
import 'package:emas_care/data/emas_repository.dart';
import 'package:emas_care/models/preview_models.dart';

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
    'Route parsing supports four roles and safely falls back for unknown paths',
    () {
      for (final r in AppRole.values) {
        final location = AppLocation.fromUri(
          Uri.parse('/${r.name}/activities'),
        );
        expect(location.role, r);
        expect(location.destination, Destination.activities);
        expect(location.uri.path, '/${r.name}/activities');
      }
      final unknown = AppLocation.fromUri(Uri.parse('/bad/route'));
      expect(unknown.role, AppRole.elder);
      expect(unknown.destination, Destination.today);
    },
  );
  testWidgets(
    'Check-in is shared with family, availability changes, and reset clears both',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MockEmasRepository();
      final c = PreviewController(repo);
      await tester.pumpWidget(EmasCareApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saya OK — I’m okay'));
      await tester.pumpAndSettle();
      expect(repo.checkedIn, true);
      c.navigate(role: AppRole.family);
      await tester.pumpAndSettle();
      expect(find.text('A hello from Dad.'), findsOneWidget);
      c.navigate(role: AppRole.helper);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('helper-availability')));
      await tester.pumpAndSettle();
      expect(repo.helperAvailable, false);
      repo.resetPreview();
      await tester.pumpAndSettle();
      expect(repo.checkedIn, false);
      expect(repo.helperAvailable, true);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      repo.dispose();
    },
  );
  testWidgets(
    'Activities filter and details navigate to the companion; wallet cannot redeem',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MockEmasRepository();
      final c = PreviewController(repo);
      await tester.pumpWidget(EmasCareApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-activities')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Community'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('activity-tai_chi')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('activity-garden')));
      await tester.pumpAndSettle();
      expect(find.text('A more comfortable way there'), findsOneWidget);
      final meet = find.text('Meet your companion');
      await tester.ensureVisible(meet);
      await tester.tap(meet);
      await tester.pumpAndSettle();
      expect(c.destination, Destination.companion);
      c.navigate(destination: Destination.rewards);
      await tester.pumpAndSettle();
      expect(find.text('Wallet not connected'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Redemption not connected'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      repo.dispose();
    },
  );
  for (final width in [320.0, 390.0, 768.0, 1440.0]) {
    testWidgets(
      'Every role and destination fits at $width px with BM and larger text',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = MockEmasRepository();
        final c = PreviewController(repo);
        await tester.pumpWidget(EmasCareApp(controller: c));
        await tester.pumpAndSettle();
        c.toggleLanguage();
        c.setPreferences(text: true, motion: true, solid: true);
        for (final role in AppRole.values) {
          c.navigate(role: role);
          for (final destination in Destination.values) {
            c.navigate(destination: destination);
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '${role.name}/${destination.name} at $width',
            );
          }
        }
        await tester.tap(find.byKey(const ValueKey('preferences')));
        await tester.pumpAndSettle();
        expect(find.text('Untuk keselesaan anda'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        repo.dispose();
      },
    );
  }
  testWidgets('Role selector, language and accessibility controls are usable', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repo = MockEmasRepository();
    final c = PreviewController(repo);
    await tester.pumpWidget(EmasCareApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('role-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Helper').last);
    await tester.pumpAndSettle();
    expect(c.role, AppRole.helper);
    await tester.tap(find.byKey(const ValueKey('language-toggle')));
    await tester.pumpAndSettle();
    expect(c.malay, true);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('helper-availability')))
          .label,
      'Sedia membantu',
    );
    await tester.tap(find.byKey(const ValueKey('preferences')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('large-text')),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    await tester.pumpAndSettle();
    expect(c.largeText, true);
    expect(
      tester
          .getSemantics(
            find.descendant(
              of: find.byKey(const ValueKey('large-text')),
              matching: find.byType(CupertinoSwitch),
            ),
          )
          .label,
      'Teks lebih besar',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
    c.dispose();
    repo.dispose();
  });
}

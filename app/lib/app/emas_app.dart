import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../data/emas_repository.dart';
import '../models/preview_models.dart';
import '../shared/design_system.dart';
import 'preview_controller.dart';
import 'app_shell.dart';
import '../data/backend_repository.dart';
import '../features/auth/sign_in_screen.dart';
import 'session_controller.dart';

class EmasCareApp extends StatefulWidget {
  const EmasCareApp({
    super.key,
    this.repository,
    this.controller,
    this.backend,
  });
  final EmasRepository? repository;
  final PreviewController? controller;
  final BackendRepository? backend;
  @override
  State<EmasCareApp> createState() => _EmasCareAppState();
}

class _EmasCareAppState extends State<EmasCareApp> {
  SemanticsHandle? _semantics;
  late final EmasRepository repository =
      widget.controller?.repository ??
      widget.repository ??
      MockEmasRepository();
  late final PreviewController controller =
      widget.controller ?? PreviewController(repository, session: session);
  late final SessionController? session = widget.backend == null
      ? null
      : SessionController(widget.backend!);
  late final _PreviewRouter router = _PreviewRouter(controller);
  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _semantics = WidgetsBinding.instance.ensureSemantics();
      unawaited(controller.inspectBrowser('check', applySystem: true));
    }
  }

  @override
  void dispose() {
    _semantics?.dispose();
    router.dispose();
    if (widget.controller == null) controller.dispose();
    session?.dispose();
    if (widget.repository == null && widget.controller == null) {
      repository.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => MaterialApp.router(
      title: 'EmasCare · Teman siang',
      debugShowCheckedModeBanner: false,
      theme: emasTheme(),
      routeInformationParser: _LocationParser(),
      routerDelegate: router,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return PreviewScope(
          controller: controller,
          child: MediaQuery(
            data: mq.copyWith(
              textScaler: TextScaler.linear(
                mq.textScaler.scale(1) * (controller.largeText ? 1.22 : 1),
              ),
              disableAnimations:
                  mq.disableAnimations || controller.reducedMotion,
              highContrast: mq.highContrast || controller.highContrast,
            ),
            child: child!,
          ),
        );
      },
    ),
  );
}

class _LocationParser extends RouteInformationParser<AppLocation> {
  @override
  Future<AppLocation> parseRouteInformation(
    RouteInformation information,
  ) async => AppLocation.fromUri(information.uri);
  @override
  RouteInformation restoreRouteInformation(AppLocation configuration) =>
      RouteInformation(uri: configuration.uri);
}

class _PreviewRouter extends RouterDelegate<AppLocation>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppLocation> {
  _PreviewRouter(this.controller) {
    controller.addListener(notifyListeners);
  }
  final PreviewController controller;
  @override
  final navigatorKey = GlobalKey<NavigatorState>();
  @override
  AppLocation get currentConfiguration => controller.location;
  @override
  Future<void> setNewRoutePath(AppLocation configuration) async {
    controller.restore(configuration);
  }

  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    pages: [
      MaterialPage(
        child:
            controller.session != null &&
                !controller.session!.preview &&
                !controller.session!.connected
            ? const SignInScreen()
            : AppShell(
                key: ValueKey(controller.session?.profile?.uid ?? 'preview'),
              ),
      ),
    ],
    onDidRemovePage: (_) {},
  );
  @override
  void dispose() {
    controller.removeListener(notifyListeners);
    super.dispose();
  }
}

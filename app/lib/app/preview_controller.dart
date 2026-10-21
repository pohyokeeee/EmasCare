import 'package:flutter/widgets.dart';
import '../data/emas_repository.dart';
import '../models/preview_models.dart';
import '../platform/browser_support.dart';
import 'session_controller.dart';
import 'community_controller.dart';
import 'companion_demo_controller.dart';
import '../data/community_repository.dart';
import '../data/session_repository.dart';
import 'session_workflow_controller.dart';

class PreviewController extends ChangeNotifier {
  PreviewController(this.repository, {this.session}) {
    repository.addListener(_repositoryChanged);
    session?.addListener(_sessionChanged);
    community?.addListener(notifyListeners);
    sessions?.addListener(notifyListeners);
    demo.addListener(notifyListeners);
  }
  final EmasRepository repository;
  final SessionController? session;
  late final SessionWorkflowController? sessions =
      session != null && session!.repository is SessionRepository
      ? SessionWorkflowController(
          session!,
          session!.repository as SessionRepository,
        )
      : null;
  late final CommunityController? community =
      session != null && session!.repository is CommunityRepository
      ? CommunityController(
          session!,
          session!.repository as CommunityRepository,
        )
      : null;
  final CompanionDemoController demo = CompanionDemoController();
  void _repositoryChanged() {
    if (demo.helperAvailable != repository.helperAvailable) {
      demo.setHelperAvailable(repository.helperAvailable);
    }
    notifyListeners();
  }

  void resetPreview() {
    repository.resetPreview();
    demo.reset();
  }

  Future<void> enterPhase2Preview() async {
    if (session != null) await session!.signOut(enterPreview: true);
    if (_disposed || session?.authError != null) return;
    navigate(role: AppRole.elder, destination: Destination.companion);
  }

  String? _lastUid;
  void _sessionChanged() {
    final p = session?.profile;
    if (p != null && session!.connected) {
      final newUser = p.uid != _lastUid;
      location = AppLocation(p.role, newUser ? Destination.today : destination);
      if (newUser) malay = p.locale == 'bm';
      _lastUid = p.uid;
    } else if (p == null) {
      _lastUid = null;
    }
    notifyListeners();
  }

  AppLocation location = const AppLocation(AppRole.elder, Destination.today);
  bool malay = false,
      largeText = false,
      reducedMotion = false,
      solidNavigation = false,
      highContrast = false;
  bool browserBusy = false;
  Map<String, dynamic>? browser;
  bool _disposed = false;
  AppRole get role => location.role;
  Destination get destination => location.destination;
  String t(String en, String bm) => malay ? bm : en;
  String roleName(AppRole role) => switch (role) {
    AppRole.elder => t('Elder', 'Warga emas'),
    AppRole.family => t('Family', 'Keluarga'),
    AppRole.helper => t('Helper', 'Pembantu'),
    AppRole.coordinator => t('Coordinator', 'Penyelaras'),
  };
  String navName(Destination d) => role == AppRole.coordinator
      ? switch (d) {
          Destination.today => t('Overview', 'Ringkasan'),
          Destination.activities => t('Requests', 'Permintaan'),
          Destination.companion => t('Places', 'Tempat'),
          Destination.rewards => t('People', 'Ahli'),
        }
      : switch (d) {
          Destination.today => t('Today', 'Hari ini'),
          Destination.activities => t('Activities', 'Aktiviti'),
          Destination.companion => t('My companion', 'Teman saya'),
          Destination.rewards =>
            role == AppRole.family
                ? t('Community', 'Komuniti')
                : t('My rewards', 'Ganjaran saya'),
        };
  void navigate({AppRole? role, Destination? destination}) {
    location = AppLocation(
      session?.connected == true ? session!.profile!.role : role ?? this.role,
      destination ?? (role == null ? this.destination : Destination.today),
    );
    notifyListeners();
  }

  void restore(AppLocation value) {
    location = session?.connected == true
        ? AppLocation(session!.profile!.role, value.destination)
        : value;
    notifyListeners();
  }

  void toggleLanguage() {
    malay = !malay;
    notifyListeners();
  }

  void setPreferences({bool? text, bool? motion, bool? solid}) {
    largeText = text ?? largeText;
    reducedMotion = motion ?? reducedMotion;
    solidNavigation = solid ?? solidNavigation;
    notifyListeners();
  }

  Future<void> inspectBrowser(String action, {bool applySystem = false}) async {
    if (browserBusy) return;
    browserBusy = true;
    notifyListeners();
    try {
      final result = await browserAction(action);
      if (_disposed) return;
      browser = result;
      if (applySystem) {
        reducedMotion = result['reducedMotion'] == true;
        solidNavigation = result['reducedTransparency'] == true;
        highContrast = result['highContrast'] == true;
      }
    } catch (_) {
      if (!_disposed) {
        browser = {
          'error': true,
          'message': t(
            'Browser check unavailable. Please try again.',
            'Semakan pelayar tidak tersedia. Cuba lagi.',
          ),
        };
      }
    }
    if (!_disposed) {
      browserBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    repository.removeListener(_repositoryChanged);
    session?.removeListener(_sessionChanged);
    community?.removeListener(notifyListeners);
    community?.dispose();
    sessions?.removeListener(notifyListeners);
    sessions?.dispose();
    demo.removeListener(notifyListeners);
    demo.dispose();
    super.dispose();
  }
}

class PreviewScope extends InheritedNotifier<PreviewController> {
  const PreviewScope({
    super.key,
    required PreviewController controller,
    required super.child,
  }) : super(notifier: controller);
  static PreviewController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PreviewScope>()!.notifier!;
}

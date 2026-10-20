import 'package:flutter/widgets.dart';
import '../data/emas_repository.dart';
import '../models/preview_models.dart';
import '../platform/browser_support.dart';

class PreviewController extends ChangeNotifier {
  PreviewController(this.repository) {
    repository.addListener(notifyListeners);
  }
  final EmasRepository repository;
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
      role ?? this.role,
      destination ?? (role == null ? this.destination : Destination.today),
    );
    notifyListeners();
  }

  void restore(AppLocation value) {
    location = value;
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
    repository.removeListener(notifyListeners);
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

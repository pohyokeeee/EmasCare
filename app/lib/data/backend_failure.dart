import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

class BackendFailure implements Exception {
  const BackendFailure(this.code, [this.reason]);
  final String code;
  final String? reason;
  factory BackendFailure.from(Object error) {
    if (error is BackendFailure) return error;
    if (error is FirebaseFunctionsException) {
      final details = error.details;
      return BackendFailure(
        error.code,
        details is Map ? details['reason'] as String? : null,
      );
    }
    if (error is FirebaseException) return BackendFailure(error.code);
    if (error is FormatException ||
        error is TypeError ||
        error is ArgumentError) {
      return const BackendFailure('invalid-data');
    }
    return const BackendFailure('unavailable');
  }
  String message(bool bm) {
    final pair = switch (reason ?? code) {
      'CHECKIN_PAUSED' => (
        'Today is paused. Unpause before checking in.',
        'Hari ini dijeda. Nyahjeda sebelum daftar masuk.',
      ),
      'INVALID_DUE_TIME' => (
        'Use a 24-hour time, such as 09:00.',
        'Gunakan masa 24 jam, seperti 09:00.',
      ),
      'INVALID_GRACE_MINUTES' => (
        'Grace minutes must be 0–1440.',
        'Minit tempoh ihsan mesti 0–1440.',
      ),
      'IDEMPOTENCY_KEY_REUSED' => (
        'This action changed. Cancel it and start a new action.',
        'Tindakan berubah. Batal dan mulakan tindakan baharu.',
      ),
      'SETTINGS_NOT_CONFIGURED' => (
        'Save your check-in settings first.',
        'Simpan tetapan daftar masuk dahulu.',
      ),
      'invalid-credential' || 'wrong-password' || 'user-not-found' => (
        'Check your email and password.',
        'Semak e-mel dan kata laluan.',
      ),
      'invalid-email' => (
        'Enter a valid email address.',
        'Masukkan alamat e-mel yang sah.',
      ),
      'too-many-requests' => (
        'Too many attempts. Try again shortly.',
        'Terlalu banyak cubaan. Cuba sebentar lagi.',
      ),
      'permission-denied' ||
      'PROFILE_REQUIRED' ||
      'ROLE_NOT_ALLOWED' ||
      'TOWNSHIP_NOT_ALLOWED' ||
      'UNRELATED_HOUSEHOLD' ||
      'CONSENT_REQUIRED' => (
        'Access is no longer permitted. Private data has been cleared.',
        'Akses tidak dibenarkan. Data peribadi telah dipadam daripada paparan.',
      ),
      'unauthenticated' ||
      'AUTH_REQUIRED' => ('Please sign in again.', 'Sila log masuk semula.'),
      'invalid-data' => (
        'The backend returned an unexpected record. Please retry.',
        'Rekod pelayan tidak dijangka. Sila cuba lagi.',
      ),
      _ => (
        'Could not reach the local backend. Check the emulators and retry.',
        'Tidak dapat menghubungi pelayan setempat. Semak emulator dan cuba lagi.',
      ),
    };
    return bm ? pair.$2 : pair.$1;
  }
}

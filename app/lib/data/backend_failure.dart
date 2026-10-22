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
      'REPORT_ACCESS_DENIED' ||
      'NOTIFICATION_ACCESS_DENIED' ||
      'PROGRESS_ACCESS_DENIED' => (
        'This information is no longer available with your current permissions. Refresh your account access and try again.',
        'Maklumat ini tidak lagi tersedia dengan kebenaran semasa. Muat semula akses akaun dan cuba lagi.',
      ),
      'VERIFIED_OUTING_REQUIRED' => (
        'Family cheers need a verified outing. Phone-only and unclassified outings cannot receive cheers.',
        'Sokongan keluarga memerlukan aktiviti keluar yang disahkan. Sesi telefon dan aktiviti belum ditakrif tidak boleh menerima sokongan.',
      ),
      'HELPER_RELATION_REQUIRED' => (
        'Choose a helper already linked to this elder through a pairing or request.',
        'Pilih pembantu yang sudah terpaut dengan warga emas ini melalui pasangan atau permintaan.',
      ),
      'SUMMARY_SUPPRESSED' => (
        'Community counts are hidden because the group is too small. Your permitted personal progress is still available.',
        'Bilangan komuniti disembunyikan kerana kumpulan terlalu kecil. Kemajuan peribadi yang dibenarkan masih tersedia.',
      ),
      'SUMMARY_NOT_CONFIGURED' || 'INVALID_SUMMARY_INPUT' => (
        'The demo availability table is not configured yet. Ask the coordinator to load the Stage 6 demo setup.',
        'Jadual ketersediaan demo belum dikonfigurasi. Minta penyelaras memuatkan persediaan demo Peringkat 6.',
      ),
      'VOICE_SERVICE_UNAVAILABLE' => (
        'Voice booking is not configured on this local backend. Use manual booking to continue.',
        'Tempahan suara belum dikonfigurasi pada pelayan setempat ini. Gunakan tempahan manual untuk meneruskan.',
      ),
      'VOICE_TIMEOUT' || 'VOICE_INVALID_RESPONSE' => (
        'The voice service could not prepare a reliable draft. Try again or use manual booking.',
        'Perkhidmatan suara tidak dapat menyediakan draf yang boleh dipercayai. Cuba lagi atau gunakan tempahan manual.',
      ),
      'VOICE_RATE_LIMIT' => (
        'Too many voice attempts this minute. Wait a little or use manual booking.',
        'Terlalu banyak cubaan suara pada minit ini. Tunggu sebentar atau gunakan tempahan manual.',
      ),
      'INVALID_AUDIO' || 'UNSUPPORTED_AUDIO_TYPE' => (
        'This recording is unsupported or too large. Record a shorter message, use text, or book manually.',
        'Rakaman ini tidak disokong atau terlalu besar. Rakam mesej lebih pendek, gunakan teks, atau tempah secara manual.',
      ),
      'HELPER_BLOCKED' || 'BLOCKED_HELPER' => (
        'This helper is blocked for this elder. Ask the coordinator for another companion.',
        'Pembantu ini disekat untuk warga emas ini. Minta penyelaras mendapatkan teman lain.',
      ),
      'INVALID_WARNING' || 'INVALID_WARNING_EXPIRY' || 'INVALID_EXPIRY' => (
        'Enter a short warning and a future review time.',
        'Masukkan amaran ringkas dan masa semakan akan datang.',
      ),
      'DEMO_LIMIT_EXCEEDED' => (
        'This demo has reached its record limit. Ask the coordinator to review the demo data.',
        'Demo ini telah mencapai had rekod. Minta penyelaras menyemak data demo.',
      ),
      'INSUFFICIENT_BALANCE' => (
        'Not enough coins. This demo voucher needs 100 coins. Pending rewards are not spendable.',
        'Syiling tidak mencukupi. Baucar demo ini memerlukan 100 syiling. Ganjaran tertunda belum boleh digunakan.',
      ),
      'VOUCHER_NOT_FOUND' ||
      'VOUCHER_NOT_AVAILABLE' ||
      'INVALID_VOUCHER_PRICE' => (
        'This demo voucher is unavailable. Refresh the wallet and check the latest catalogue.',
        'Baucar demo ini tidak tersedia. Muat semula dompet dan semak katalog terkini.',
      ),
      'WALLET_REQUIRED' => (
        'Your saved wallet is unavailable. Ask the coordinator to check your account, then retry.',
        'Dompet tersimpan anda tidak tersedia. Minta penyelaras menyemak akaun anda, kemudian cuba semula.',
      ),
      'INVALID_WALLET_BALANCE' ||
      'REDEMPTION_ACCOUNTING_CONFLICT' ||
      'REWARD_ACCOUNTING_CONFLICT' ||
      'REWARD_RECIPIENT_MISMATCH' ||
      'COMPLETION_NOT_VERIFIED' ||
      'INVALID_PARTICIPATION_LINK' => (
        'This record needs an account check. Refresh your wallet and ask the coordinator for help.',
        'Rekod ini memerlukan semakan akaun. Muat semula dompet dan minta bantuan penyelaras.',
      ),
      'HELPER_UNAVAILABLE' => (
        'This companion is unavailable for the whole session. Choose another pairing or change the time.',
        'Teman ini tidak tersedia sepanjang sesi. Pilih pasangan lain atau ubah masa.',
      ),
      'HELPER_BUSY' => (
        'The companion is still helping in another session. Try again after it finishes.',
        'Teman masih membantu dalam sesi lain. Cuba selepas sesi itu tamat.',
      ),
      'PAIRING_NOT_ELIGIBLE' || 'HELPER_BLOCKED' => (
        'This pairing cannot take this request. Review the pairing, task and preferences.',
        'Pasangan ini tidak boleh menerima permintaan. Semak pasangan, tugas dan pilihan.',
      ),
      'SESSION_NOT_STARTED' => (
        'The scheduled start time has not arrived yet.',
        'Masa mula yang dijadualkan belum tiba.',
      ),
      'ACTIVITY_NOT_FINISHED' => (
        'Wait until the activity ends before submitting attendance or finishing the session.',
        'Tunggu sehingga aktiviti tamat sebelum menghantar kehadiran atau menamatkan sesi.',
      ),
      'ATTENDANCE_MANAGED_BY_SESSION' => (
        'This activity is managed through your companion session. Complete both confirmations in My companion.',
        'Aktiviti ini diurus melalui sesi teman anda. Lengkapkan kedua-dua pengesahan dalam Teman saya.',
      ),
      'ATTENDANCE_ALREADY_REVIEWED' => (
        'This attendance has already been reviewed. Close the form and check the latest record.',
        'Kehadiran ini telah disemak. Tutup borang dan semak rekod terkini.',
      ),
      'ACTIVITY_NOT_IN_PERSON' ||
      'INVALID_ACTIVITY_SCHEDULE' ||
      'INVALID_ATTENDANCE_LINK' => (
        'Attendance needs a valid, finished in-person activity. Ask the coordinator to check its details.',
        'Kehadiran memerlukan aktiviti bersemuka yang sah dan telah tamat. Minta penyelaras menyemak butirannya.',
      ),
      'INVALID_REVIEW_DECISION' ||
      'INVALID_VERIFICATION_METHOD' ||
      'INVALID_REVIEW_NOTE' => (
        'Choose a review decision, a verification method when verifying, and a note of 1–500 characters.',
        'Pilih keputusan semakan, kaedah apabila mengesahkan, dan nota 1–500 aksara.',
      ),
      'ACTIVITY_ALREADY_FINISHED' => (
        'This activity has ended and the session can no longer be started.',
        'Aktiviti ini telah tamat dan sesi tidak boleh dimulakan lagi.',
      ),
      'INVALID_TRANSITION' => (
        'This session has changed. Review its latest status before continuing.',
        'Sesi ini telah berubah. Semak status terkini sebelum meneruskan.',
      ),
      'ACTIVITY_REQUEST_EXISTS' => (
        'An active request already exists for this activity. Find it in My companion.',
        'Permintaan aktif untuk aktiviti ini sudah wujud. Lihat dalam Teman saya.',
      ),
      'ACTIVITY_ALREADY_COMPLETED' => (
        'Participation in this activity has already been recorded.',
        'Penyertaan aktiviti ini sudah direkodkan.',
      ),
      'ATTENDANCE_ALREADY_SUBMITTED' => (
        'An attendance record already exists for this activity. Ask the coordinator to review it.',
        'Rekod kehadiran aktiviti ini sudah wujud. Minta penyelaras menyemaknya.',
      ),
      'INVALID_TIME_RANGE' || 'ACTIVITY_SCHEDULE_MISMATCH' => (
        'Choose a future session with a valid duration. Activity requests use the full activity schedule.',
        'Pilih sesi akan datang dengan tempoh sah. Permintaan aktiviti mengikut jadual penuh aktiviti.',
      ),
      'INVALID_AVAILABILITY' => (
        'Check the weekly hours. Each interval must end after it starts and cannot overlap another interval.',
        'Semak waktu mingguan. Setiap selang mesti tamat selepas bermula dan tidak boleh bertindih.',
      ),
      'REQUEST_NOT_FOUND' ||
      'PLACE_NOT_FOUND' ||
      'ACTIVITY_NOT_FOUND' ||
      'ATTENDANCE_NOT_FOUND' => (
        'This record is no longer available. Refresh the list and choose again.',
        'Rekod ini tidak lagi tersedia. Muat semula senarai dan pilih semula.',
      ),
      'INVALID_PLACE' ||
      'INVALID_PREFERENCES' ||
      'INVALID_TASK' ||
      'INVALID_PAYLOAD' ||
      'UNKNOWN_FIELD' ||
      'invalid-argument' => (
        'Review the request details and try again.',
        'Semak butiran permintaan dan cuba lagi.',
      ),
      'ELDER_HOUSEHOLD_REQUIRED' || 'HELPER_PROFILE_REQUIRED' => (
        'Your account needs a configured household or helper profile. Ask the coordinator to check it.',
        'Akaun memerlukan isi rumah atau profil pembantu yang lengkap. Minta penyelaras menyemaknya.',
      ),
      'failed-precondition' => (
        'This action is not available in the current state. Review the latest details.',
        'Tindakan ini tidak tersedia dalam keadaan semasa. Semak butiran terkini.',
      ),
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
      'ELDER_ACCESS_DENIED' ||
      'ATTENDANCE_ACCESS_DENIED' ||
      'WALLET_ACCESS_DENIED' ||
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

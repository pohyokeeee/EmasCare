import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/backend_models.dart';
import 'backend_repository.dart';

/// Local-only adapter. No SDK read, listener or callable starts before connect.
class FirebaseBackendRepository implements BackendRepository {
  FirebaseBackendRepository._(this.auth, this.db, this.functions);
  final FirebaseAuth auth;
  final FirebaseFirestore db;
  final FirebaseFunctions functions;
  static Future<FirebaseBackendRepository> connect() async {
    if (!['127.0.0.1', 'localhost', '::1'].contains(Uri.base.host)) {
      throw StateError('This build requires a loopback browser origin.');
    }
    final app = await Firebase.initializeApp(
      name: 'emascare-local',
      options: const FirebaseOptions(
        apiKey: 'local-demo-key',
        appId: '1:1234567890:web:emascare-demo',
        messagingSenderId: '1234567890',
        projectId: 'demo-emascare',
        authDomain: 'demo-emascare.firebaseapp.com',
      ),
    );
    final auth = FirebaseAuth.instanceFor(app: app);
    final db = FirebaseFirestore.instanceFor(app: app);
    final functions = FirebaseFunctions.instanceFor(
      app: app,
      region: 'asia-southeast1',
    );
    await auth.useAuthEmulator('127.0.0.1', 9099, automaticHostMapping: false);
    await auth.setPersistence(Persistence.SESSION);
    db.settings = const Settings(persistenceEnabled: false);
    db.useFirestoreEmulator('127.0.0.1', 8080, automaticHostMapping: false);
    functions.useFunctionsEmulator(
      '127.0.0.1',
      5001,
      automaticHostMapping: false,
    );
    return FirebaseBackendRepository._(auth, db, functions);
  }

  @override
  Stream<String?> authChanges() => auth.authStateChanges().map((u) => u?.uid);
  @override
  Future<void> signIn(String email, String password) async {
    await auth.signInWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> signOut() => auth.signOut();
  @override
  Stream<BackendProfile?> watchProfile(String uid) => db
      .doc('users/$uid')
      .snapshots(includeMetadataChanges: true)
      .where((s) => !s.metadata.isFromCache)
      .map(
        (s) => s.exists
            ? BackendProfile.fromJson({...s.data()!, 'uid': s.id})
            : null,
      );
  @override
  Future<BackendProfile> getBackendContext() async => BackendProfile.fromJson(
    jsonObject((await _call('getBackendContext', {}))['profile']),
  );
  Future<Json> _call(String name, Json fields) async {
    final response = await functions.httpsCallable(name).call<Object?>({
      'contractVersion': 1,
      ...fields,
    });
    return unwrapEnvelope(response.data);
  }

  static Json unwrapEnvelope(Object? value) {
    final envelope = jsonObject(value);
    if (envelope['contractVersion'] != 1) {
      throw const FormatException('Contract version');
    }
    return jsonObject(envelope['data']);
  }

  @override
  Stream<ElderSettings?> watchSettings(String uid) => db
      .doc('elderSettings/$uid')
      .snapshots(includeMetadataChanges: true)
      .where((s) => !s.metadata.isFromCache)
      .map(
        (s) => s.exists
            ? ElderSettings.fromJson({...s.data()!, 'id': s.id})
            : null,
      );
  Stream<List<CheckInRecord>> _checkins(Query<Json> query) => query
      .snapshots(includeMetadataChanges: true)
      .where((s) => !s.metadata.isFromCache)
      .map(
        (s) => s.docs
            .map((d) => CheckInRecord.fromJson({...d.data(), 'id': d.id}))
            .toList(),
      );
  @override
  Stream<List<CheckInRecord>> watchCheckIns(String uid) => _checkins(
    db
        .collection('checkins')
        .where('elderId', isEqualTo: uid)
        .orderBy('localDate', descending: true),
  );
  @override
  Stream<HouseholdAccess> watchHousehold(BackendProfile profile) => db
      .doc('households/${profile.householdId}')
      .snapshots(includeMetadataChanges: true)
      .where((s) => !s.metadata.isFromCache)
      .map((s) => HouseholdAccess.fromJson(s.data() ?? {}, profile));
  @override
  Stream<List<DailyStatus>> watchDailyStatuses(
    String elderId,
    String householdId,
  ) => db
      .collection('dailyStatuses')
      .where('elderId', isEqualTo: elderId)
      .where('householdId', isEqualTo: householdId)
      .orderBy('localDate', descending: true)
      .snapshots(includeMetadataChanges: true)
      .where((s) => !s.metadata.isFromCache)
      .map(
        (s) => s.docs
            .map((d) => DailyStatus.fromJson({...d.data(), 'id': d.id}))
            .toList(),
      );
  @override
  Stream<List<CheckInRecord>> watchExceptions(String townshipId, String date) =>
      _checkins(
        db
            .collection('checkins')
            .where('townshipId', isEqualTo: townshipId)
            .where('localDate', isEqualTo: date)
            .where('state', whereIn: ['reminded', 'missed'])
            .orderBy('dueAt'),
      );
  @override
  Future<ElderSettings> saveElderSettings(Json payload, String key) async =>
      ElderSettings.fromJson(
        jsonObject(
          (await _call('saveElderSettings', {
            ...payload,
            'idempotencyKey': key,
          }))['settings'],
        ),
      );
  Future<(CheckInRecord, DailyStatus)> _response(
    String name,
    Json fields,
  ) async {
    final data = await _call(name, fields);
    return (
      CheckInRecord.fromJson(jsonObject(data['checkin'])),
      DailyStatus.fromJson(jsonObject(data['dailyStatus'])),
    );
  }

  @override
  Future<(CheckInRecord, DailyStatus)> submitCheckIn(String key) =>
      _response('submitCheckIn', {'idempotencyKey': key});
  @override
  Future<(CheckInRecord, DailyStatus)> recordPhoneResponse(
    String elderId,
    String key,
  ) => _response('recordPhoneResponse', {
    'idempotencyKey': key,
    'elderId': elderId,
  });
}

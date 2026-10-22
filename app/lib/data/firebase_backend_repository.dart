import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/backend_models.dart';
import 'backend_repository.dart';
import 'community_repository.dart';
import 'session_repository.dart';
import '../models/session_models.dart';
import '../models/community_models.dart';
import '../models/preview_models.dart';
import 'attendance_repository.dart';
import '../models/attendance_models.dart';

/// Local-only adapter. No SDK read, listener or callable starts before connect.
class FirebaseBackendRepository
    implements
        BackendRepository,
        CommunityRepository,
        SessionRepository,
        AttendanceRepository {
  FirebaseBackendRepository._(this.auth, this.db, this.functions);
  final FirebaseAuth auth;
  final FirebaseFirestore db;
  final FirebaseFunctions functions;

  @override
  Stream<List<ActivityAttendance>> watchAttendance(
    BackendProfile profile, {
    String? elderId,
  }) {
    if (profile.role == AppRole.helper) return const Stream.empty();
    Query<Json> q = db.collection('activityAttendances');
    q = switch (profile.role) {
      AppRole.elder =>
        q
            .where('elderId', isEqualTo: profile.uid)
            .orderBy('createdAt', descending: true),
      AppRole.family =>
        q
            .where('elderId', isEqualTo: elderId!)
            .where('householdId', isEqualTo: profile.householdId!)
            .orderBy('createdAt', descending: true),
      AppRole.coordinator =>
        q
            .where('townshipId', isEqualTo: profile.townshipId)
            .where('status', isEqualTo: 'submitted')
            .orderBy('submittedAt'),
      AppRole.helper => throw StateError(
        'Helper attendance reads are not permitted',
      ),
    };
    return q
        .snapshots(includeMetadataChanges: true)
        .where((s) => !s.metadata.isFromCache)
        .map(
          (s) => s.docs
              .map(
                (d) => ActivityAttendance.fromJson({...d.data(), 'id': d.id}),
              )
              .toList(),
        );
  }

  Future<ActivityAttendance> _attendanceCall(
    String name,
    Json fields,
    String key,
  ) async => ActivityAttendance.fromJson(
    jsonObject(
      (await _call(name, {...fields, 'idempotencyKey': key}))['attendance'],
    ),
  );
  @override
  Future<ActivityAttendance> submitActivityAttendance(
    Json fields,
    String key,
  ) => _attendanceCall('submitActivityAttendance', fields, key);
  @override
  Future<ActivityAttendance> reviewActivityAttendance(
    Json fields,
    String key,
  ) => _attendanceCall('reviewActivityAttendance', fields, key);
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

  @override
  Stream<List<ActivityRecord>> watchActivities(String townshipId) => db
      .collection('activities')
      .where('townshipId', isEqualTo: townshipId)
      .orderBy('startsAt')
      .snapshots(includeMetadataChanges: true)
      .where((s) => !s.metadata.isFromCache)
      .map(
        (s) => s.docs
            .map((d) => ActivityRecord.fromJson({...d.data(), 'id': d.id}))
            .toList(),
      );
  @override
  Stream<List<PlaceRecord>> watchPlaces(String townshipId) => db
      .collection('places')
      .where('townshipId', isEqualTo: townshipId)
      .snapshots(includeMetadataChanges: true)
      .where((s) => !s.metadata.isFromCache)
      .map(
        (s) => s.docs
            .map((d) => PlaceRecord.fromJson({...d.data(), 'id': d.id}))
            .toList(),
      );
  @override
  Stream<List<PairingRecord>> watchPairings(BackendProfile profile) {
    Query<Json> query = db.collection('pairings');
    query = switch (profile.role) {
      AppRole.elder =>
        query
            .where('elderId', isEqualTo: profile.uid)
            .where('townshipId', isEqualTo: profile.townshipId),
      AppRole.helper =>
        query
            .where('helperId', isEqualTo: profile.uid)
            .where('townshipId', isEqualTo: profile.townshipId),
      AppRole.coordinator =>
        query
            .where('townshipId', isEqualTo: profile.townshipId)
            .where('active', isEqualTo: true),
      AppRole.family => throw StateError(
        'Family pairing reads are not authorized.',
      ),
    };
    return query
        .snapshots(includeMetadataChanges: true)
        .where((s) => !s.metadata.isFromCache)
        .map(
          (s) => s.docs
              .map((d) => PairingRecord.fromJson({...d.data(), 'id': d.id}))
              .toList(),
        );
  }

  @override
  Stream<HelperProfileRecord?> watchHelperProfile(String uid) => db
      .doc('helperProfiles/$uid')
      .snapshots(includeMetadataChanges: true)
      .where((s) => !s.metadata.isFromCache)
      .map(
        (s) => s.exists
            ? HelperProfileRecord.fromJson({...s.data()!, 'id': s.id})
            : null,
      );

  @override
  Stream<List<SessionRequest>> watchRequests(
    BackendProfile profile, {
    String? elderId,
    RequestState queue = RequestState.requested,
  }) {
    Query<Json> q = db.collection('requests');
    q = switch (profile.role) {
      AppRole.elder =>
        q
            .where('elderId', isEqualTo: profile.uid)
            .orderBy('startsAt', descending: true),
      AppRole.family =>
        q
            .where('elderId', isEqualTo: elderId!)
            .where('householdId', isEqualTo: profile.householdId!)
            .orderBy('startsAt', descending: true),
      AppRole.helper =>
        q
            .where('helperId', isEqualTo: profile.uid)
            .where('townshipId', isEqualTo: profile.townshipId)
            .orderBy('startsAt'),
      AppRole.coordinator =>
        q
            .where('townshipId', isEqualTo: profile.townshipId)
            .where('state', isEqualTo: queue.wire)
            .orderBy('startsAt'),
    };
    return q
        .snapshots(includeMetadataChanges: true)
        .where((s) => !s.metadata.isFromCache)
        .map(
          (s) => s.docs
              .map((d) => SessionRequest.fromJson({...d.data(), 'id': d.id}))
              .toList(),
        );
  }

  @override
  Future<HelperProfileRecord> setHelperAvailability(
    Json fields,
    String key,
  ) async => HelperProfileRecord.fromJson(
    jsonObject(
      (await _call('setHelperAvailability', {
        ...fields,
        'idempotencyKey': key,
      }))['helperProfile'],
    ),
  );
  Future<SessionRequest> _requestCall(
    String name,
    Json fields,
    String key,
  ) async => SessionRequest.fromJson(
    jsonObject(
      (await _call(name, {...fields, 'idempotencyKey': key}))['request'],
    ),
  );
  @override
  Future<SessionRequest> createRequest(Json fields, String key) =>
      _requestCall('createRequest', fields, key);
  @override
  Future<SessionRequest> assignRequest(Json fields, String key) =>
      _requestCall('assignRequest', fields, key);
  @override
  Future<SessionRequest> transitionRequest(Json fields, String key) =>
      _requestCall('transitionRequest', fields, key);
}

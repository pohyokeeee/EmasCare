import '../models/backend_models.dart';

abstract interface class BackendRepository {
  Stream<String?> authChanges();
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Stream<BackendProfile?> watchProfile(String uid);
  Future<BackendProfile> getBackendContext();
  Stream<ElderSettings?> watchSettings(String uid);
  Stream<List<CheckInRecord>> watchCheckIns(String uid);
  Stream<HouseholdAccess> watchHousehold(BackendProfile profile);
  Stream<List<DailyStatus>> watchDailyStatuses(
    String elderId,
    String householdId,
  );
  Stream<List<CheckInRecord>> watchExceptions(String townshipId, String date);
  Future<ElderSettings> saveElderSettings(Json payload, String key);
  Future<(CheckInRecord, DailyStatus)> submitCheckIn(String key);
  Future<(CheckInRecord, DailyStatus)> recordPhoneResponse(
    String elderId,
    String key,
  );
}

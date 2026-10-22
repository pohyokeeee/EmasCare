import '../models/backend_models.dart';

const coordinationReads = {
  'getProgress',
  'getAvailabilitySummary',
  'getCoordinatorSummary',
  'parseVoiceBooking',
};
const coordinationMutations = {
  'setPlaceWarning',
  'submitReport',
  'reviewReport',
  'blockHelper',
  'sendFamilyCheer',
  'markNotificationRead',
  'processDemoDueItems',
};

abstract interface class CoordinationRepository {
  Future<Json> coordinationCall(
    String name,
    Json fields, {
    String? idempotencyKey,
  });
  Stream<List<Json>> watchCoordinationReports(
    BackendProfile profile, {
    String? requestId,
    String? elderId,
    String? householdId,
  });
  Stream<List<Json>> watchNotices(
    BackendProfile profile,
    String elderId,
    String consentScope,
  );
  Stream<List<Json>> watchCheers(String elderId);
  Stream<List<Json>> watchTownshipElders(BackendProfile profile);
  Stream<List<Json>> watchHelperBlocks(BackendProfile profile);
}

import '../models/backend_models.dart';
import '../models/community_models.dart';
import '../models/session_models.dart';

abstract interface class SessionRepository {
  Stream<List<SessionRequest>> watchRequests(
    BackendProfile profile, {
    String? elderId,
    RequestState queue = RequestState.requested,
  });
  Future<HelperProfileRecord> setHelperAvailability(Json fields, String key);
  Future<SessionRequest> createRequest(Json fields, String key);
  Future<SessionRequest> assignRequest(Json fields, String key);
  Future<SessionRequest> transitionRequest(Json fields, String key);
}

import '../models/backend_models.dart';
import '../models/community_models.dart';

/// Read APIs already documented by B. Stage 3 mutations are intentionally absent.
abstract interface class CommunityRepository {
  Stream<List<ActivityRecord>> watchActivities(String townshipId);
  Stream<List<PlaceRecord>> watchPlaces(String townshipId);
  Stream<List<PairingRecord>> watchPairings(BackendProfile profile);
  Stream<HelperProfileRecord?> watchHelperProfile(String uid);
}

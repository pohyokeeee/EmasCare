import '../models/backend_models.dart';
import '../models/community_models.dart';

/// Optional live availability API. It is separate from helper profiles so
/// family members can signal that they are open to a future companion request
/// without becoming assignable helpers or exposing private profile fields.
abstract interface class AvailabilityRepository {
  Stream<CompanionAvailabilityRecord?> watchCompanionAvailability(String uid);
  Future<CompanionAvailabilityRecord> setCompanionAvailability(
    Json fields,
    String key,
  );
}

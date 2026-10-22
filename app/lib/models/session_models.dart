import 'backend_models.dart';

enum RequestState {
  requested,
  assigned,
  accepted,
  inProgress,
  awaitingConfirmation,
  completed,
  cancelled;

  String get wire => switch (this) {
    inProgress => 'in_progress',
    awaitingConfirmation => 'awaiting_confirmation',
    _ => name,
  };
  static RequestState parse(String value) =>
      values.firstWhere((s) => s.wire == value);
}

class SessionConfirmation {
  SessionConfirmation.fromJson(Json data)
    : uid = data['uid'] as String,
      at = utcTimestamp(data['at'])!;
  final String uid;
  final DateTime at;
}

class SessionRequest {
  SessionRequest.fromJson(Json data)
    : id = data['id'] as String,
      townshipId = data['townshipId'] as String,
      householdId = data['householdId'] as String,
      elderId = data['elderId'] as String,
      createdBy = data['createdBy'] as String,
      activityId = data['activityId'] as String?,
      placeId = data['placeId'] as String?,
      startsAt = utcTimestamp(data['startsAt'])!,
      endsAt = utcTimestamp(data['endsAt'])!,
      taskType = data['taskType'] as String,
      preferredLanguage = data['preferredLanguage'] as String,
      preferredHelperGender = data['preferredHelperGender'] as String,
      state = RequestState.parse(data['state'] as String),
      pairingId = data['pairingId'] as String?,
      helperId = data['helperId'] as String?,
      elderName = data['elderDisplayName'] as String,
      helperName = data['helperDisplay'] == null
          ? null
          : jsonObject(data['helperDisplay'])['displayName'] as String?,
      helperTier = data['helperDisplay'] == null
          ? null
          : jsonObject(data['helperDisplay'])['tier'] as String?,
      elderConfirmation = data['elderConfirmation'] == null
          ? null
          : SessionConfirmation.fromJson(jsonObject(data['elderConfirmation'])),
      helperConfirmation = data['helperConfirmation'] == null
          ? null
          : SessionConfirmation.fromJson(
              jsonObject(data['helperConfirmation']),
            ),
      assignedAt = utcTimestamp(data['assignedAt']),
      acceptedAt = utcTimestamp(data['acceptedAt']),
      startedAt = utcTimestamp(data['startedAt']),
      finishedAt = utcTimestamp(data['finishedAt']),
      cancelledAt = utcTimestamp(data['cancelledAt']),
      completedAt = utcTimestamp(data['completedAt']),
      completionEventId = data['completionEventId'] as String?,
      participationIds = jsonObject(data['participationIds']),
      createdAt = utcTimestamp(data['createdAt'])!,
      updatedAt = utcTimestamp(data['updatedAt'])!;
  final String id,
      townshipId,
      householdId,
      elderId,
      createdBy,
      taskType,
      preferredLanguage,
      preferredHelperGender,
      elderName;
  final String? activityId,
      placeId,
      pairingId,
      helperId,
      helperName,
      helperTier,
      completionEventId;
  final DateTime startsAt, endsAt, createdAt, updatedAt;
  final DateTime? assignedAt,
      acceptedAt,
      startedAt,
      finishedAt,
      cancelledAt,
      completedAt;
  final RequestState state;
  final SessionConfirmation? elderConfirmation, helperConfirmation;
  final Json participationIds;
  bool get elderConfirmed => elderConfirmation?.uid == elderId;
  bool get helperConfirmed =>
      helperId != null && helperConfirmation?.uid == helperId;
  bool get cancellable => [
    RequestState.requested,
    RequestState.assigned,
    RequestState.accepted,
  ].contains(state);
}

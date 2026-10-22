import 'backend_models.dart';

enum AttendanceStatus { submitted, verified, rejected }

class ActivityAttendance {
  ActivityAttendance.fromJson(Json data)
    : id = data['id'] as String,
      townshipId = data['townshipId'] as String,
      householdId = data['householdId'] as String,
      activityId = data['activityId'] as String,
      elderId = data['elderId'] as String,
      mode = data['mode'] as String,
      status = AttendanceStatus.values.byName(data['status'] as String),
      linkedRequestId = data['linkedRequestId'] as String?,
      submittedAt = utcTimestamp(data['submittedAt']),
      verifiedAt = utcTimestamp(data['verifiedAt']),
      verificationMethod = data['verificationMethod'] as String?,
      reviewedBy = data['reviewedBy'] as String?,
      reviewedAt = utcTimestamp(data['reviewedAt']),
      reviewNote = data['reviewNote'] as String?,
      completionEventId = data['completionEventId'] as String?,
      participationId = data['participationId'] as String?,
      createdAt = utcTimestamp(data['createdAt'])!,
      updatedAt = utcTimestamp(data['updatedAt'])!;
  final String id, townshipId, householdId, activityId, elderId, mode;
  final AttendanceStatus status;
  final String? linkedRequestId,
      verificationMethod,
      reviewedBy,
      reviewNote,
      completionEventId,
      participationId;
  final DateTime? submittedAt, verifiedAt, reviewedAt;
  final DateTime createdAt, updatedAt;
  bool get sessionManaged => mode == 'companion_session';
  bool get reviewable =>
      mode == 'standalone' && status == AttendanceStatus.submitted;
}

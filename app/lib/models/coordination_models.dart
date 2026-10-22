import 'backend_models.dart';

int countValue(Object? value) {
  if (value is! int || value < 0) throw const FormatException('Invalid count');
  return value;
}

class ProgressRecord {
  ProgressRecord.fromJson(Json j)
    : id = j['id'] as String,
      scope = j['scope'] as String,
      entityId = j['entityId'] as String,
      periodType = j['periodType'] as String,
      periodKey = j['periodKey'] as String,
      counts = {
        for (final e in jsonObject(j['counts']).entries)
          e.key: countValue(e.value),
      },
      targets = {
        for (final e in jsonObject(j['targets']).entries)
          e.key: e.value == null ? null : countValue(e.value),
      },
      pendingClassifications = countValue(j['pendingOutingClassifications']),
      latestOuting = j['latestOuting'] == null
          ? null
          : jsonObject(j['latestOuting']),
      isDemo = j['isDemo'] == true,
      includesSeededHistory = j['includesSeededHistory'] == true,
      updatedAt = utcTimestamp(j['updatedAt'])! {
    for (final key in ['outings', 'helpingSessions', 'weekendGiveBack']) {
      if (!counts.containsKey(key) ||
          !targets.containsKey(key) ||
          (targets[key] != null && targets[key]! <= 0)) {
        throw const FormatException('Invalid progress metric');
      }
    }
    if (!['elder', 'helper', 'household', 'township'].contains(scope) ||
        !['week', 'month'].contains(periodType)) {
      throw const FormatException('Invalid progress scope');
    }
  }
  final String id, scope, entityId, periodType, periodKey;
  final Map<String, int> counts;
  final Map<String, int?> targets;
  final int pendingClassifications;
  final Json? latestOuting;
  final bool isDemo, includesSeededHistory;
  final DateTime updatedAt;
}

class ReportRecord {
  ReportRecord.fromJson(Json j)
    : id = j['id'] as String,
      townshipId = j['townshipId'] as String,
      createdBy = j['createdBy'] as String,
      kind = j['kind'] as String,
      text = j['text'] as String,
      state = j['state'] as String,
      placeId = j['placeId'] as String?,
      requestId = j['requestId'] as String?,
      helperId = j['helperId'] as String?,
      elderId = j['elderId'] as String?,
      createdAt = utcTimestamp(j['createdAt'])!,
      reviewedAt = utcTimestamp(j['reviewedAt']) {
    if (!['new', 'seen', 'done'].contains(state)) {
      throw const FormatException('Invalid report state');
    }
  }
  final String id, townshipId, createdBy, kind, text, state;
  final String? placeId, requestId, helperId, elderId;
  final DateTime createdAt;
  final DateTime? reviewedAt;
}

class NoticeRecord {
  NoticeRecord.fromJson(Json j)
    : id = j['id'] as String,
      recipientUid = j['recipientUid'] as String,
      elderId = j['elderId'] as String,
      kind = j['kind'] as String,
      entityId = j['entityId'] as String,
      consentScope = j['consentScope'] as String,
      messageParams = jsonObject(j['messageParams']),
      readAt = utcTimestamp(j['readAt']),
      createdAt = utcTimestamp(j['createdAt'])!;
  final String id, recipientUid, elderId, kind, entityId, consentScope;
  final Json messageParams;
  final DateTime? readAt;
  final DateTime createdAt;
}

class VoiceBookingResult {
  VoiceBookingResult.fromJson(Json j)
    : transcript = j['transcript'] as String,
      draft = j['draft'] == null ? null : jsonObject(j['draft']),
      missingFields = List<String>.from(j['missingFields'] as List),
      clarification = j['clarification'] as String?,
      readBackText = j['readBackText'] as String?,
      canConfirm = j['canConfirm'] == true {
    if (canConfirm &&
        (draft == null || missingFields.isNotEmpty || readBackText == null)) {
      throw const FormatException('Incomplete voice confirmation');
    }
  }
  final String transcript;
  final Json? draft;
  final List<String> missingFields;
  final String? clarification, readBackText;
  final bool canConfirm;
}

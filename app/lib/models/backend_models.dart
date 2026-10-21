import 'package:cloud_firestore/cloud_firestore.dart';
import 'preview_models.dart';

typedef Json = Map<String, dynamic>;

Json jsonObject(Object? value) => Map<String, dynamic>.from(value as Map);
DateTime? utcTimestamp(Object? value) => switch (value) {
  null => null,
  Timestamp t => t.toDate().toUtc(),
  DateTime t => t.toUtc(),
  String t => DateTime.parse(t).toUtc(),
  _ => throw const FormatException('Invalid timestamp'),
};
String malaysiaDate(DateTime now) => now
    .toUtc()
    .add(const Duration(hours: 8))
    .toIso8601String()
    .substring(0, 10);
String malaysiaTime(DateTime? time) => time == null
    ? '—'
    : time
          .toUtc()
          .add(const Duration(hours: 8))
          .toIso8601String()
          .substring(11, 16);

class BackendProfile {
  BackendProfile.fromJson(Json data)
    : uid = data['uid'] as String,
      displayName = data['displayName'] as String,
      role = AppRole.values.byName(data['role'] as String),
      townshipId = data['townshipId'] as String,
      householdId = data['householdId'] as String?,
      locale = data['locale'] as String {
    if (uid.isEmpty || townshipId.isEmpty || !['en', 'bm'].contains(locale)) {
      throw const FormatException('Invalid profile');
    }
  }
  final String uid, displayName, townshipId, locale;
  final String? householdId;
  final AppRole role;
  bool sameScope(BackendProfile other) =>
      uid == other.uid &&
      role == other.role &&
      townshipId == other.townshipId &&
      householdId == other.householdId;
}

class ElderSettings {
  ElderSettings.fromJson(Json data)
    : id = data['id'] as String,
      sharing = data['familySharingEnabled'] as bool,
      booking = data['familyBookingEnabled'] as bool,
      dueLocalTime = data['dueLocalTime'] as String,
      graceMinutes = data['graceMinutes'] as int,
      pausedOn = data['pausedOn'] as String?,
      createdAt = utcTimestamp(data['createdAt'])!,
      updatedAt = utcTimestamp(data['updatedAt'])!;
  final String id, dueLocalTime;
  final String? pausedOn;
  final bool sharing, booking;
  final int graceMinutes;
  final DateTime createdAt, updatedAt;
  bool pausedToday(DateTime now) => pausedOn == malaysiaDate(now);
}

enum CheckInState { pending, reminded, missed, ok, paused }

/// Only the permitted family projection; private check-in fields are not kept.
class DailyStatus {
  DailyStatus.fromJson(Json data)
    : id = data['id'] as String,
      elderId = data['elderId'] as String,
      householdId = data['householdId'] as String,
      localDate = data['localDate'] as String,
      state = CheckInState.values.byName(data['state'] as String),
      submittedAt = utcTimestamp(data['submittedAt']),
      updatedAt = utcTimestamp(data['updatedAt'])!;
  final String id, elderId, householdId, localDate;
  final CheckInState state;
  final DateTime? submittedAt;
  final DateTime updatedAt;
}

class CheckInRecord {
  CheckInRecord.fromJson(Json data)
    : id = data['id'] as String,
      elderId = data['elderId'] as String,
      townshipId = data['townshipId'] as String,
      localDate = data['localDate'] as String,
      state = CheckInState.values.byName(data['state'] as String),
      dueAt = utcTimestamp(data['dueAt'])!,
      graceEndsAt = utcTimestamp(data['graceEndsAt'])!,
      submittedAt = utcTimestamp(data['submittedAt']),
      recordedBy = data['recordedBy'] as String?,
      source = data['source'] as String?,
      createdAt = utcTimestamp(data['createdAt'])!,
      updatedAt = utcTimestamp(data['updatedAt'])!;
  final String id, elderId, townshipId, localDate;
  final String? recordedBy, source;
  final CheckInState state;
  final DateTime dueAt, graceEndsAt, createdAt, updatedAt;
  final DateTime? submittedAt;
}

class ElderAccess {
  ElderAccess(this.id, Json data)
    : displayName = data['displayName'] as String,
      sharing = data['familySharingEnabled'] == true,
      booking = data['familyBookingEnabled'] == true;
  final String id, displayName;
  final bool sharing, booking;
}

class HouseholdAccess {
  HouseholdAccess.fromJson(Json data, BackendProfile profile) {
    final members = List<String>.from(data['memberUids'] as List);
    final family = List<String>.from(data['familyUids'] as List);
    if (data['townshipId'] != profile.townshipId ||
        !members.contains(profile.uid) ||
        !family.contains(profile.uid)) {
      throw const FormatException('Unrelated household');
    }
    final access = jsonObject(data['elderAccess']);
    elders = [
      for (final id in List<String>.from(data['elderIds'] as List))
        if (access[id] is Map) ElderAccess(id, jsonObject(access[id])),
    ];
  }
  late final List<ElderAccess> elders;
}

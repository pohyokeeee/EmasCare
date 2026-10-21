import 'backend_models.dart';
import 'preview_models.dart';

DateTime malaysiaWallTime(DateTime time) =>
    time.toUtc().add(const Duration(hours: 8));
String activityDate(DateTime time, bool bm) {
  final t = malaysiaWallTime(time);
  final days = bm
      ? ['Isn', 'Sel', 'Rab', 'Kha', 'Jum', 'Sab', 'Ahd']
      : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final months = bm
      ? [
          'Jan',
          'Feb',
          'Mac',
          'Apr',
          'Mei',
          'Jun',
          'Jul',
          'Ogo',
          'Sep',
          'Okt',
          'Nov',
          'Dis',
        ]
      : [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
  return '${days[t.weekday - 1]}, ${t.day} ${months[t.month - 1]}';
}

LocalText localizedRecord(Object? value) {
  if (value is String) return LocalText(value, value);
  final data = jsonObject(value);
  return LocalText(
    (data['en'] ?? data['bm'] ?? '') as String,
    (data['bm'] ?? data['en'] ?? '') as String,
  );
}

class ActivityRecord {
  ActivityRecord.fromJson(Json data)
    : id = data['id'] as String,
      townshipId = data['townshipId'] as String,
      title = localizedRecord(data['title']),
      placeId = data['placeId'] as String,
      startsAt = utcTimestamp(data['startsAt'])!,
      endsAt = utcTimestamp(data['endsAt'])!,
      language = data['language'] as String,
      participationMode = data['participationMode'] as String;
  final String id, townshipId, placeId, language, participationMode;
  final LocalText title;
  final DateTime startsAt, endsAt;
}

class PlaceNotice {
  PlaceNotice.fromJson(Json data)
    : level = data['level'] as String,
      text = localizedRecord(data['text']),
      expiresAt = utcTimestamp(data['expiresAt']),
      updatedAt = utcTimestamp(data['updatedAt']);
  final String level;
  final LocalText text;
  final DateTime? expiresAt, updatedAt;
  bool activeAt(DateTime now) =>
      expiresAt == null || now.toUtc().isBefore(expiresAt!);
}

class PlaceRecord {
  PlaceRecord.fromJson(Json data)
    : id = data['id'] as String,
      townshipId = data['townshipId'] as String,
      name = data['name'] as String,
      stepFree = data['stepFree'] as bool?,
      toilet = data['accessibleToilet'] as bool?,
      seating = data['seating'] as bool?,
      walkMinutes = data['walkMinutes'] as int?,
      notes = localizedRecord(data['notes'] ?? {}),
      mapsUrl = data['mapsUrl'] as String?,
      notice = data['liveStatus'] == null
          ? null
          : PlaceNotice.fromJson(jsonObject(data['liveStatus']));
  final String id, townshipId, name;
  final bool? stepFree, toilet, seating;
  final int? walkMinutes;
  final LocalText notes;
  final String? mapsUrl;
  final PlaceNotice? notice;
  Uri? get mapsLink {
    final uri = Uri.tryParse(mapsUrl ?? '');
    if (uri?.scheme != 'https') return null;
    final host = uri!.host.toLowerCase();
    return ['maps.google.com', 'maps.app.goo.gl'].contains(host) ||
            (['google.com', 'www.google.com'].contains(host) &&
                uri.path.startsWith('/maps'))
        ? uri
        : null;
  }
}

class PairingRecord {
  PairingRecord.fromJson(Json data)
    : id = data['id'] as String,
      townshipId = data['townshipId'] as String,
      elderId = data['elderId'] as String,
      helperId = data['helperId'] as String,
      active = data['active'] == true,
      elderAccepted = data['elderAccepted'] == true,
      helperAccepted = data['helperAccepted'] == true,
      trialStartsOn = data['trialStartsOn'] as String?,
      trialEndsOn = data['trialEndsOn'] as String?,
      demoSeed = data['isDemoSeed'] == true;
  final String id, townshipId, elderId, helperId;
  final bool active, elderAccepted, helperAccepted, demoSeed;
  final String? trialStartsOn, trialEndsOn;
  bool get accepted => active && elderAccepted && helperAccepted;
}

class HelperProfileRecord {
  HelperProfileRecord.fromJson(Json data)
    : id = data['id'] as String,
      approved = data['approved'] == true,
      available = data['available'] == true,
      languages = List<String>.from(data['languages'] as List),
      tasks = List<String>.from(data['allowedTasks'] as List),
      slots = [
        for (final s in data['availabilitySlots'] as List) jsonObject(s),
      ],
      tier = data['tier'] as String?,
      gender = data['gender'] as String?,
      createdAt = utcTimestamp(data['createdAt']),
      updatedAt = utcTimestamp(data['updatedAt']);
  final String id;
  final String? tier, gender;
  final DateTime? createdAt, updatedAt;
  final bool approved, available;
  final List<String> languages, tasks;
  final List<Json> slots;
}

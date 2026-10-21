import '../models/backend_models.dart';
import '../models/community_models.dart';

/// UI fixtures kept outside connected Firestore state. Dates follow rehearsal day.
List<ActivityRecord> sampleActivities(DateTime now) {
  final today = malaysiaDate(now);
  final start = DateTime.parse('${today}T10:00:00+08:00');
  return [
    for (final (index, id, title, bm, place) in [
      (1, 'tai_chi', 'Morning tai chi', 'Tai chi pagi', 'sample_park'),
      (
        2,
        'garden',
        'A little time in the garden',
        'Bersantai di kebun',
        'sample_garden',
      ),
      (
        3,
        'lakeside',
        'Lakeside morning walk',
        'Jalan pagi di tasik',
        'sample_lake',
      ),
    ])
      ActivityRecord.fromJson({
        'id': id,
        'townshipId': 'sample_township',
        'title': {'en': title, 'bm': bm},
        'placeId': place,
        'startsAt': start.add(Duration(days: index)),
        'endsAt': start.add(Duration(days: index, hours: 1)),
        'language': 'en',
        'participationMode': 'in_person',
      }),
  ];
}

List<PlaceRecord> samplePlaces(DateTime now) => [
  for (final (id, name, minutes, stepFree) in [
    ('sample_park', 'Central Park · Gate B', 6, true),
    ('sample_garden', 'Ilham Community Garden', 4, true),
    ('sample_lake', 'Elmina Lakeside', 8, false),
  ])
    PlaceRecord.fromJson({
      'id': id,
      'townshipId': 'sample_township',
      'name': name,
      'walkMinutes': minutes,
      'stepFree': stepFree,
      'accessibleToilet': stepFree,
      'seating': true,
      'notes': {
        'en': 'Sample access information. Check conditions before leaving.',
        'bm': 'Maklumat akses contoh. Semak keadaan sebelum keluar.',
      },
      'mapsUrl': 'https://maps.google.com/?q=${Uri.encodeComponent(name)}',
      'liveStatus': id == 'sample_garden'
          ? {
              'level': 'warning',
              'text': {
                'en':
                    'Sample notice: the garden path is wet. Ask the coordinator about an alternative entrance.',
                'bm':
                    'Notis contoh: laluan kebun basah. Tanya penyelaras tentang pintu masuk alternatif.',
              },
              'updatedAt': now,
              'expiresAt': now.add(const Duration(hours: 4)),
            }
          : null,
    }),
];

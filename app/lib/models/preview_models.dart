/// UI view models only. Wire JSON is pending agreement with Developer B.
enum AppRole { elder, family, helper, coordinator }

enum Destination { today, activities, companion, rewards }

class AppLocation {
  const AppLocation(this.role, this.destination);
  final AppRole role;
  final Destination destination;
  Uri get uri => Uri(path: '/${role.name}/${destination.name}');

  factory AppLocation.fromUri(Uri uri) {
    final parts = uri.pathSegments;
    return AppLocation(
      AppRole.values
              .where((r) => parts.isNotEmpty && r.name == parts[0])
              .firstOrNull ??
          AppRole.elder,
      Destination.values
              .where((d) => parts.length > 1 && d.name == parts[1])
              .firstOrNull ??
          Destination.today,
    );
  }
}

class LocalText {
  const LocalText(this.en, this.bm);
  final String en;
  final String bm;
  String inLanguage(bool malay) => malay ? bm : en;
}

class CommunityActivity {
  const CommunityActivity({
    required this.id,
    required this.title,
    required this.description,
    required this.day,
    required this.time,
    required this.place,
    required this.walkMinutes,
    this.garden = false,
  });
  final String id;
  final LocalText title, description, day;
  final String time, place;
  final int walkMinutes;
  final bool garden;
}

class RequestPreview {
  const RequestPreview(
    this.name,
    this.initials,
    this.activity,
    this.time,
    this.assigned,
  );
  final String name, initials, activity, time;
  final bool assigned;
}

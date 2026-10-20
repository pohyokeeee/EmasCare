import 'package:flutter/foundation.dart';
import '../models/preview_models.dart';

/// Local interface seam. No callable names or JSON schemas are approved here.
/// Developer B's adapter can replace this when the response contract is agreed.
abstract class EmasRepository extends ChangeNotifier {
  List<CommunityActivity> get activities;
  List<RequestPreview> get requests;
  bool get checkedIn;
  bool get helperAvailable;
  void previewCheckIn();
  void previewSetAvailability(bool value);
  void resetPreview();
}

class MockEmasRepository extends EmasRepository {
  bool _checkedIn = false;
  bool _available = true;
  @override
  bool get checkedIn => _checkedIn;
  @override
  bool get helperAvailable => _available;
  @override
  final activities = const [
    CommunityActivity(
      id: 'tai_chi',
      title: LocalText('Morning tai chi', 'Tai chi pagi'),
      description: LocalText(
        'A gentle start to the day, together. Beginners are welcome.',
        'Mulakan hari bersama dengan senaman ringan. Pemula dialu-alukan.',
      ),
      day: LocalText('Tomorrow', 'Esok'),
      time: '10:00–11:00',
      place: 'Central Park · Gate B',
      walkMinutes: 6,
    ),
    CommunityActivity(
      id: 'garden',
      title: LocalText('A little time in the garden', 'Bersantai di kebun'),
      description: LocalText(
        'Meet your neighbours, tend a few plants and share a cup of tea.',
        'Jumpa jiran, jaga tanaman dan minum teh bersama.',
      ),
      day: LocalText('Friday', 'Jumaat'),
      time: '09:00–10:00',
      place: 'Ilham Community Garden',
      walkMinutes: 4,
      garden: true,
    ),
    CommunityActivity(
      id: 'lakeside',
      title: LocalText('Lakeside morning walk', 'Jalan pagi di tasik'),
      description: LocalText(
        'An easy walk with plenty of places to pause and enjoy the view.',
        'Jalan santai dengan tempat rehat dan pemandangan indah.',
      ),
      day: LocalText('Saturday', 'Sabtu'),
      time: '08:30–09:30',
      place: 'Elmina Lakeside',
      walkMinutes: 8,
    ),
  ];
  @override
  final requests = const [
    RequestPreview('Mr Tan', 'MT', 'Morning tai chi', 'Thu · 10:00', true),
    RequestPreview(
      'Puan Rohani',
      'PR',
      'Community garden',
      'Fri · 09:00',
      false,
    ),
    RequestPreview('Uncle Lim', 'UL', 'Lakeside walk', 'Sat · 08:30', false),
  ];
  @override
  void previewCheckIn() {
    if (_checkedIn) return;
    _checkedIn = true;
    notifyListeners();
  }

  @override
  void previewSetAvailability(bool value) {
    if (_available == value) return;
    _available = value;
    notifyListeners();
  }

  @override
  void resetPreview() {
    _checkedIn = false;
    _available = true;
    notifyListeners();
  }
}

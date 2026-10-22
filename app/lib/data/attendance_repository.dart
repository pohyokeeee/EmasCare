import '../models/attendance_models.dart';
import '../models/backend_models.dart';

abstract interface class AttendanceRepository {
  Stream<List<ActivityAttendance>> watchAttendance(
    BackendProfile profile, {
    String? elderId,
  });
  Future<ActivityAttendance> submitActivityAttendance(Json fields, String key);
  Future<ActivityAttendance> reviewActivityAttendance(Json fields, String key);
}

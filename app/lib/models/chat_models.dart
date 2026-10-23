import 'backend_models.dart';

class SessionMessage {
  SessionMessage.fromJson(Json data)
    : id = data['id'] as String,
      requestId = data['requestId'] as String,
      senderUid = data['senderUid'] as String,
      senderRole = data['senderRole'] as String,
      text = data['text'] as String,
      createdAt = utcTimestamp(data['createdAt'])!;

  final String id, requestId, senderUid, senderRole, text;
  final DateTime createdAt;
}

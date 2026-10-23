import '../models/chat_models.dart';

abstract interface class ChatRepository {
  Future<List<SessionMessage>> listSessionMessages(
    String requestId, {
    int limit = 100,
  });
  Future<SessionMessage> sendSessionMessage(
    String requestId,
    String text,
    String key,
  );
}

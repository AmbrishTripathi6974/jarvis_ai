import 'dart:typed_data';

import 'package:jarvis/features/chat/domain/entities/chat_message.dart';

abstract class ChatRepository {
  Stream<String> sendMessage({
    required ChatMessage userMessage,
    Uint8List? imageBytes,
    String? imageMimeType,
    List<ChatMessage>? historyOverride,
    bool persistUserMessage = true,
    int? responseMessageId,
  });

  Future<List<ChatMessage>> getChatHistory();

  Future<void> saveMessage(ChatMessage message);

  Future<void> deleteMessagesByIds(List<int> ids);

  Future<void> clearChat();
}

import 'dart:typed_data';

import 'package:jarvis/features/chat/domain/entities/chat_message.dart';
import 'package:jarvis/features/chat/domain/repositories/chat_repository.dart';

class SendMessage {
  const SendMessage(this._repository);

  final ChatRepository _repository;

  Stream<String> call({
    required ChatMessage userMessage,
    Uint8List? imageBytes,
    String? imageMimeType,
    List<ChatMessage>? historyOverride,
    bool persistUserMessage = true,
    int? responseMessageId,
  }) {
    return _repository.sendMessage(
      userMessage: userMessage,
      imageBytes: imageBytes,
      imageMimeType: imageMimeType,
      historyOverride: historyOverride,
      persistUserMessage: persistUserMessage,
      responseMessageId: responseMessageId,
    );
  }
}

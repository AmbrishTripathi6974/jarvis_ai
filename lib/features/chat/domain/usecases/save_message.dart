import 'package:jarvis/features/chat/domain/entities/chat_message.dart';
import 'package:jarvis/features/chat/domain/repositories/chat_repository.dart';

class SaveMessage {
  const SaveMessage(this._repository);

  final ChatRepository _repository;

  Future<void> call(ChatMessage message) => _repository.saveMessage(message);
}


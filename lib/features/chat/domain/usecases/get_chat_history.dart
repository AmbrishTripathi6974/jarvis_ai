import 'package:jarvis/features/chat/domain/entities/chat_message.dart';
import 'package:jarvis/features/chat/domain/repositories/chat_repository.dart';

class GetChatHistory {
  const GetChatHistory(this._repository);

  final ChatRepository _repository;

  Future<List<ChatMessage>> call() => _repository.getChatHistory();
}

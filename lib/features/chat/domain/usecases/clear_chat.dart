import 'package:jarvis/features/chat/domain/repositories/chat_repository.dart';

class ClearChat {
  const ClearChat(this._repository);

  final ChatRepository _repository;

  Future<void> call() => _repository.clearChat();
}

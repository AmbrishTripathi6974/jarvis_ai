import 'package:jarvis/features/chat/domain/repositories/chat_repository.dart';

class DeleteMessagesByIds {
  const DeleteMessagesByIds(this._repository);

  final ChatRepository _repository;

  Future<void> call(List<int> ids) => _repository.deleteMessagesByIds(ids);
}


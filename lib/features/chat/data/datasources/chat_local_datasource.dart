import 'package:isar/isar.dart';
import 'package:jarvis/features/chat/data/models/chat_message_model.dart';

abstract class ChatLocalDataSource {
  Future<List<ChatMessageModel>> getChatHistory();
  Future<void> saveMessage(ChatMessageModel message);
  Future<void> deleteMessagesByIds(List<int> ids);
  Future<void> clearChat();
}

class ChatLocalDataSourceImpl implements ChatLocalDataSource {
  const ChatLocalDataSourceImpl(this._isar);

  final Isar _isar;

  @override
  Future<void> clearChat() async {
    await _isar.writeTxn(_isar.chatMessageModels.clear);
  }

  @override
  Future<List<ChatMessageModel>> getChatHistory() {
    return _isar.chatMessageModels.where().sortByTimestamp().findAll();
  }

  @override
  Future<void> saveMessage(ChatMessageModel message) async {
    await _isar.writeTxn(() => _isar.chatMessageModels.put(message));
  }

  @override
  Future<void> deleteMessagesByIds(List<int> ids) async {
    if (ids.isEmpty) {
      return;
    }

    await _isar.writeTxn(() => _isar.chatMessageModels.deleteAll(ids));
  }
}

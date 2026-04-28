import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_message.freezed.dart';

enum ChatMessageStatus {
  sent,
  pending,
  streaming,
  failed,
  incomplete,
}

@freezed
class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required int id,
    required String content,
    required bool isUser,
    required DateTime timestamp,
    @Default(ChatMessageStatus.sent) ChatMessageStatus status,
    String? imagePath,
    String? failureReason,
  }) = _ChatMessage;
}

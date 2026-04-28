import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:jarvis/features/chat/domain/entities/chat_message.dart';

part 'chat_message_model.g.dart';

@collection
@JsonSerializable()
class ChatMessageModel {
  ChatMessageModel({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.status = ChatMessageStatus.sent,
    this.imagePath,
    this.failureReason,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageModelFromJson(json);

  factory ChatMessageModel.fromEntity(ChatMessage entity) {
    return ChatMessageModel(
      id: entity.id,
      content: entity.content,
      isUser: entity.isUser,
      timestamp: entity.timestamp,
      status: entity.status,
      imagePath: entity.imagePath,
      failureReason: entity.failureReason,
    );
  }

  Id id;
  String content;
  bool isUser;
  DateTime timestamp;
  @enumerated
  ChatMessageStatus status;
  String? imagePath;
  String? failureReason;

  Map<String, dynamic> toJson() => _$ChatMessageModelToJson(this);

  ChatMessage toEntity() {
    return ChatMessage(
      id: id,
      content: content,
      isUser: isUser,
      timestamp: timestamp,
      status: status,
      imagePath: imagePath,
      failureReason: failureReason,
    );
  }
}

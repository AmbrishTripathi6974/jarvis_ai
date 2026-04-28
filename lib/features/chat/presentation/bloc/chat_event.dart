import 'dart:typed_data';

abstract class ChatEvent {
  const ChatEvent();
}

class ConnectivityChangedEvent extends ChatEvent {
  const ConnectivityChangedEvent(this.isOnline);

  final bool isOnline;
}

class SendMessageEvent extends ChatEvent {
  const SendMessageEvent({
    required this.text,
    this.imageBytes,
    this.imageMimeType,
  });

  final String text;
  final Uint8List? imageBytes;
  final String? imageMimeType;
}

class ReceiveStreamChunkEvent extends ChatEvent {
  const ReceiveStreamChunkEvent(this.chunk);

  final String chunk;
}

class RevealNextWordEvent extends ChatEvent {
  const RevealNextWordEvent();
}

class StreamCompletedEvent extends ChatEvent {
  const StreamCompletedEvent();
}

class StreamFailedEvent extends ChatEvent {
  const StreamFailedEvent({
    required this.message,
    this.userMessageId,
    this.forceUserRetry = false,
  });

  final String message;
  final int? userMessageId;
  final bool forceUserRetry;
}

class StreamStalledEvent extends ChatEvent {
  const StreamStalledEvent();
}

class RateLimitTickEvent extends ChatEvent {
  const RateLimitTickEvent(this.remaining);

  final Duration? remaining;
}

class RetryMessageEvent extends ChatEvent {
  const RetryMessageEvent(this.messageId);

  final int messageId;
}

class ContinueAssistantResponseEvent extends ChatEvent {
  const ContinueAssistantResponseEvent(this.assistantMessageId);

  final int assistantMessageId;
}

class DeleteTurnEvent extends ChatEvent {
  const DeleteTurnEvent(this.userMessageId);

  final int userMessageId;
}

class LoadChatHistoryEvent extends ChatEvent {
  const LoadChatHistoryEvent();
}

class ClearChatEvent extends ChatEvent {
  const ClearChatEvent();
}

import 'package:jarvis/features/chat/domain/entities/chat_message.dart';

abstract class ChatState {
  const ChatState({
    required this.messages,
    required this.isStreaming,
    required this.isMutating,
    this.isAwaitingServer = false,
    this.hasIncompleteAssistantResponse = false,
    this.rateLimitRemaining,
    this.errorMessage,
  });

  final List<ChatMessage> messages;
  final bool isStreaming;
  final bool isMutating;
  final bool isAwaitingServer;
  final bool hasIncompleteAssistantResponse;
  final Duration? rateLimitRemaining;
  final String? errorMessage;
}

class ChatInitial extends ChatState {
  const ChatInitial()
      : super(messages: const [], isStreaming: false, isMutating: false);
}

class ChatLoading extends ChatState {
  const ChatLoading({
    required super.messages,
    required super.isStreaming,
    super.isMutating = false,
    super.isAwaitingServer = false,
    super.hasIncompleteAssistantResponse = false,
    super.rateLimitRemaining,
    super.errorMessage,
  });
}

class ChatStreaming extends ChatState {
  const ChatStreaming({
    required super.messages,
    required super.isStreaming,
    super.isMutating = false,
    super.isAwaitingServer = false,
    super.hasIncompleteAssistantResponse = false,
    super.rateLimitRemaining,
    super.errorMessage,
  });
}

class ChatLoaded extends ChatState {
  const ChatLoaded({
    required super.messages,
    required super.isStreaming,
    super.isMutating = false,
    super.isAwaitingServer = false,
    super.hasIncompleteAssistantResponse = false,
    super.rateLimitRemaining,
    super.errorMessage,
  });
}

class ChatError extends ChatState {
  const ChatError({
    required super.messages,
    required super.isStreaming,
    super.isMutating = false,
    super.isAwaitingServer = false,
    super.hasIncompleteAssistantResponse = false,
    super.rateLimitRemaining,
    super.errorMessage,
  });
}

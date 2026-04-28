import 'dart:async';
import 'dart:typed_data';

import 'package:jarvis/core/error/exceptions.dart';
import 'package:jarvis/core/error/failures.dart';
import 'package:jarvis/features/chat/data/datasources/chat_local_datasource.dart';
import 'package:jarvis/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:jarvis/features/chat/data/models/chat_message_model.dart';
import 'package:jarvis/features/chat/domain/entities/chat_message.dart';
import 'package:jarvis/features/chat/domain/repositories/chat_repository.dart';

class ChatRepositoryImpl implements ChatRepository {
  const ChatRepositoryImpl(this._remoteDataSource, this._localDataSource);

  final ChatRemoteDataSource _remoteDataSource;
  final ChatLocalDataSource _localDataSource;

  @override
  Future<void> clearChat() async {
    try {
      await _localDataSource.clearChat();
    } on Exception catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<List<ChatMessage>> getChatHistory() async {
    try {
      final messages = await _localDataSource.getChatHistory();
      return messages.map((message) => message.toEntity()).toList();
    } on Exception catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Stream<String> sendMessage({
    required ChatMessage userMessage,
    Uint8List? imageBytes,
    String? imageMimeType,
    List<ChatMessage>? historyOverride,
    bool persistUserMessage = true,
    int? responseMessageId,
  }) async* {
    try {
      if (persistUserMessage) {
        await _localDataSource.saveMessage(ChatMessageModel.fromEntity(userMessage));
      }
      final history =
          historyOverride ??
          (await _localDataSource.getChatHistory())
              .map((message) => message.toEntity())
              .toList();

      final aiBuffer = StringBuffer();
      await for (final chunk in _remoteDataSource.sendMessage(
        history: history,
        imageBytes: imageBytes,
        imageMimeType: imageMimeType,
      )) {
        aiBuffer.write(chunk);
        yield chunk;
      }

      final trimmedResponse = aiBuffer.toString().trim();
      if (trimmedResponse.isNotEmpty) {
        final aiMessage = ChatMessage(
          // Keep a stable id so UI and local storage stay in sync.
          // The ChatBloc uses `userMessage.id + 1` for normal turns.
          id: responseMessageId ?? userMessage.id + 1,
          content: trimmedResponse,
          isUser: false,
          timestamp: DateTime.now(),
          status: ChatMessageStatus.sent,
        );
        await _localDataSource.saveMessage(ChatMessageModel.fromEntity(aiMessage));
      }
    } on Exception catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<void> saveMessage(ChatMessage message) async {
    try {
      await _localDataSource.saveMessage(ChatMessageModel.fromEntity(message));
    } on Exception catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<void> deleteMessagesByIds(List<int> ids) async {
    try {
      await _localDataSource.deleteMessagesByIds(ids);
    } on Exception catch (error) {
      throw _mapError(error);
    }
  }

  Failure _mapError(Exception error) {
    return switch (error) {
      NetworkException(:final message) => NetworkFailure(message),
      RequestTimeoutException(:final message) => TimeoutFailure(message),
      StreamingException(:final message) => StreamingFailure(message),
      RateLimitException(:final message, :final retryAfter) => RateLimitFailure(
        message,
        retryAfter: retryAfter,
      ),
      ServerException(:final message) => ServerFailure(message),
      Failure() => error,
      _ => const ServerFailure('Something went wrong. Please try again.'),
    };
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:jarvis/core/error/exceptions.dart';
import 'package:jarvis/core/network/dio_client.dart';
import 'package:jarvis/core/utils/constants.dart';
import 'package:jarvis/features/chat/domain/entities/chat_message.dart';

abstract class ChatRemoteDataSource {
  Stream<String> sendMessage({
    required List<ChatMessage> history,
    Uint8List? imageBytes,
    String? imageMimeType,
  });
}

class ChatRemoteDataSourceImpl implements ChatRemoteDataSource {
  const ChatRemoteDataSourceImpl(this._dioClient);

  final DioClient _dioClient;

  @override
  Stream<String> sendMessage({
    required List<ChatMessage> history,
    Uint8List? imageBytes,
    String? imageMimeType,
  }) async* {
    if (AppConstants.geminiApiKey.isEmpty) {
      throw const ServerException(
        'Missing Gemini API key. Add GEMINI_API_KEY to the local .env file.',
      );
    }

    final models = AppConstants.geminiModelFailoverChain;
    DioException? lastDioError;

    for (var i = 0; i < models.length; i++) {
      final model = models[i];
      try {
        final response = await _dioClient.postStream(
          uri: AppConstants.geminiStreamUri(model: model),
          headers: {'x-goog-api-key': AppConstants.geminiApiKey},
          data: _buildBody(
            history: history,
            imageBytes: imageBytes,
            imageMimeType: imageMimeType,
          ),
        );

        final stream = response.data?.stream;
        if (stream == null) {
          throw const StreamingException('Empty streaming response received.');
        }

        var lastAggregatedText = '';
        final lines = stream
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter());

        await for (final line in lines) {
          if (!line.startsWith('data: ')) {
            continue;
          }

          final payload = line.substring(6).trim();
          if (payload.isEmpty || payload == '[DONE]') {
            continue;
          }

          final decoded = jsonDecode(payload);
          final aggregatedText = _extractText(decoded);
          if (aggregatedText.isEmpty) {
            continue;
          }

          if (aggregatedText.startsWith(lastAggregatedText)) {
            final delta = aggregatedText.substring(lastAggregatedText.length);
            if (delta.isNotEmpty) {
              yield delta;
            }
          } else {
            yield aggregatedText;
          }

          lastAggregatedText = aggregatedText;
        }

        // Completed successfully: exit.
        return;
      } on DioException catch (error) {
        lastDioError = error;
        if (_isQuotaOrRateLimitError(error) && i < models.length - 1) {
          // Failover to next model.
          continue;
        }
        _rethrowAsAppException(error);
      }
    }

    if (lastDioError != null) {
      _rethrowAsAppException(lastDioError);
    }
  }

  bool _isQuotaOrRateLimitError(DioException error) {
    final code = error.response?.statusCode;
    if (code == 429) {
      return true;
    }
    if (code == 503 || code == 500) {
      final message = (error.response?.statusMessage ?? error.message ?? '')
          .toLowerCase();
      return message.contains('quota') ||
          message.contains('resource_exhausted') ||
          message.contains('rate limit') ||
          message.contains('too many');
    }
    return false;
  }

  Never _rethrowAsAppException(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      throw const RequestTimeoutException(
        'Request timed out. Please try again.',
      );
    }

    if (error.type == DioExceptionType.connectionError) {
      throw const NetworkException(
        'No internet connection. Please check your network.',
      );
    }

    if (error.response?.statusCode == 429) {
      final retryAfter = _parseRetryAfter(error.response?.headers);
      throw RateLimitException(
        retryAfter == null
            ? 'Too many requests right now. Please wait a moment and try again.'
            : 'Too many requests right now. Please wait ${retryAfter.inSeconds}s and try again.',
        retryAfter: retryAfter,
      );
    }

    final status = error.response?.statusCode;
    final statusText = error.response?.statusMessage;
    final message = (statusText?.trim().isNotEmpty == true ? statusText : null) ??
        (error.message?.trim().isNotEmpty == true ? error.message : null) ??
        'Gemini API failed.';

    throw ServerException(status == null ? message : 'HTTP $status: $message');
  }

  Map<String, dynamic> _buildBody({
    required List<ChatMessage> history,
    Uint8List? imageBytes,
    String? imageMimeType,
  }) {
    final trimmedHistory = history
        .where((message) => message.content.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final recentHistory = trimmedHistory.length > 20
        ? trimmedHistory.sublist(trimmedHistory.length - 20)
        : trimmedHistory;

    final latestUserMessageId = recentHistory
        .lastWhere(
          (message) => message.isUser,
          orElse: () => ChatMessage(
            id: -1,
            content: '',
            isUser: true,
            timestamp: DateTime.fromMillisecondsSinceEpoch(0),
            status: ChatMessageStatus.sent,
          ),
        )
        .id;

    final contents = recentHistory.map((message) {
      final parts = <Map<String, dynamic>>[];

      final shouldAttachImage =
          imageBytes != null &&
          message.isUser &&
          message.id == latestUserMessageId;

      if (shouldAttachImage) {
        parts.add({
          'inline_data': {
            'mime_type': imageMimeType ?? 'image/jpeg',
            'data': base64Encode(imageBytes),
          },
        });
      }

      parts.add({'text': message.content});
      return {
        'role': message.isUser ? 'user' : 'model',
        'parts': parts,
      };
    }).toList();

    return {
      'system_instruction': {
        'parts': [
          {
            'text':
                'You are JARVIS, a helpful conversational assistant. Reply naturally, remember prior turns from the provided chat history, and keep answers focused on the user request.',
          },
        ],
      },
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 1024,
      },
      'contents': contents,
    };
  }

  String _extractText(dynamic decoded) {
    final candidates = decoded['candidates'];
    if (candidates is! List) {
      return '';
    }

    final buffer = StringBuffer();
    for (final candidate in candidates) {
      final parts = candidate['content']?['parts'];
      if (parts is! List) {
        continue;
      }

      for (final part in parts) {
        final text = part['text'];
        if (text is String && text.isNotEmpty) {
          buffer.write(text);
        }
      }
    }

    return buffer.toString();
  }

  Duration? _parseRetryAfter(Headers? headers) {
    final value = headers?.value('retry-after');
    if (value == null) {
      return const Duration(seconds: 30);
    }

    final seconds = int.tryParse(value);
    if (seconds != null && seconds > 0) {
      return Duration(seconds: seconds);
    }

    return const Duration(seconds: 30);
  }
}

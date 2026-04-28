import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis/core/error/failures.dart';
import 'package:jarvis/core/network/connectivity_cubit.dart';
import 'package:jarvis/core/storage/image_storage.dart';
import 'package:jarvis/features/chat/domain/entities/chat_message.dart';
import 'package:jarvis/features/chat/domain/repositories/chat_repository.dart';
import 'package:jarvis/features/chat/domain/usecases/clear_chat.dart';
import 'package:jarvis/features/chat/domain/usecases/delete_messages_by_ids.dart';
import 'package:jarvis/features/chat/domain/usecases/get_chat_history.dart';
import 'package:jarvis/features/chat/domain/usecases/save_message.dart';
import 'package:jarvis/features/chat/domain/usecases/send_message.dart';
import 'package:jarvis/features/chat/presentation/bloc/chat_bloc.dart';
import 'package:jarvis/features/chat/presentation/bloc/chat_event.dart';
import 'package:jarvis/features/chat/presentation/bloc/chat_state.dart';
import 'package:jarvis/main.dart';

void main() {
  test('reveals streamed assistant text word-by-word', () async {
    final repository = _FakeChatRepository();
    final controller = StreamController<String>();
    repository.activeStreamController = controller;
    final chatBloc = _createChatBloc(repository);
    addTearDown(() async {
      if (!controller.isClosed) {
        await controller.close();
      }
      await chatBloc.close();
    });

    chatBloc.add(const SendMessageEvent(text: 'Hello JARVIS'));
    await Future<void>.delayed(Duration.zero);

    controller.add('One two three ');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(chatBloc.state.messages.last.content, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(chatBloc.state.messages.last.content, 'One ');

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(chatBloc.state.messages.last.content, 'One two ');

    await controller.close();
    await Future<void>.delayed(const Duration(milliseconds: 90));

    expect(chatBloc.state.messages.last.content, 'One two three ');
    expect(chatBloc.state.messages.last.status, ChatMessageStatus.sent);
  });

  test('keeps partial assistant text and marks it incomplete on stream failure', () async {
    final repository = _FakeChatRepository();
    final controller = StreamController<String>();
    repository.activeStreamController = controller;
    final chatBloc = _createChatBloc(repository);
    addTearDown(() async {
      if (!controller.isClosed) {
        await controller.close();
      }
      await chatBloc.close();
    });

    chatBloc.add(const SendMessageEvent(text: 'Explain this'));
    await Future<void>.delayed(Duration.zero);

    controller.add('Alpha beta gamma ');
    await Future<void>.delayed(const Duration(milliseconds: 320));
    controller.addError(const StreamingFailure('Stream interrupted.'));
    await Future<void>.delayed(const Duration(milliseconds: 180));

    final messages = chatBloc.state.messages;
    expect(messages.last.content, contains('Alpha beta gamma'));
    expect(messages.last.status, ChatMessageStatus.incomplete);
    expect(messages.first.status, ChatMessageStatus.sent);
    expect(
      repository.storedMessages.any(
        (message) =>
            !message.isUser &&
            message.status == ChatMessageStatus.incomplete &&
            message.content.contains('Alpha beta gamma'),
      ),
      isTrue,
    );
  });

  test('marks user message failed for service unavailable errors', () async {
    final repository = _FakeChatRepository();
    final controller = StreamController<String>();
    repository.activeStreamController = controller;
    final chatBloc = _createChatBloc(repository);
    addTearDown(() async {
      if (!controller.isClosed) {
        await controller.close();
      }
      await chatBloc.close();
    });

    chatBloc.add(const SendMessageEvent(text: 'Need the server response'));
    await Future<void>.delayed(Duration.zero);

    controller.add('Partial content ');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    controller.addError(const ServerFailure('Service Unavailable'));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final messages = chatBloc.state.messages;
    expect(messages.length, 1);
    expect(messages.single.isUser, isTrue);
    expect(messages.single.status, ChatMessageStatus.failed);
    expect(messages.single.failureReason, 'Server unavailable. Tap to retry.');
  });

  testWidgets('renders chat page title', (WidgetTester tester) async {
    final repository = _FakeChatRepository();
    final chatBloc = _createChatBloc(repository);
    addTearDown(chatBloc.close);
    final connectivityCubit = ConnectivityCubit.fromStream(Stream<bool>.value(true));
    addTearDown(connectivityCubit.close);
    await tester.pumpWidget(
      MyApp(chatBloc: chatBloc, connectivityCubit: connectivityCubit),
    );
    await tester.pump();

    expect(find.text('JARVIS'), findsOneWidget);
  });

  testWidgets('shows shimmer loading view while chat history is loading', (
    WidgetTester tester,
  ) async {
    final repository = _FakeChatRepository();
    final chatBloc = _createChatBloc(repository);
    addTearDown(chatBloc.close);
    final connectivityCubit = ConnectivityCubit.fromStream(Stream<bool>.value(true));
    addTearDown(connectivityCubit.close);

    await tester.pumpWidget(
      MyApp(chatBloc: chatBloc, connectivityCubit: connectivityCubit),
    );

    chatBloc.add(
      _EmitLoadingStateEvent(
        const ChatLoading(messages: [], isStreaming: false),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Restoring conversation content'), findsWidgets);
  });

  testWidgets('shows continue action for incomplete assistant replies', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final repository = _FakeChatRepository()
      ..storedMessages.addAll([
        ChatMessage(
          id: 1,
          content: 'Tell me something useful',
          isUser: true,
          timestamp: now,
        ),
        ChatMessage(
          id: 2,
          content: 'Here is a partial answer',
          isUser: false,
          timestamp: now.add(const Duration(seconds: 1)),
          status: ChatMessageStatus.incomplete,
          failureReason: 'The response paused before finishing.',
        ),
      ]);
    final chatBloc = _createChatBloc(repository);
    addTearDown(chatBloc.close);
    final connectivityCubit = ConnectivityCubit.fromStream(Stream<bool>.value(true));
    addTearDown(connectivityCubit.close);

    await tester.pumpWidget(
      MyApp(chatBloc: chatBloc, connectivityCubit: connectivityCubit),
    );
    chatBloc.add(const LoadChatHistoryEvent());
    await tester.pump();
    await tester.pump();

    expect(find.text('Here is a partial answer'), findsOneWidget);
    expect(find.text('Continue response'), findsOneWidget);
  });

  testWidgets('hides Latest chip after chat is cleared', (
    WidgetTester tester,
  ) async {
    final repository = _FakeChatRepository()
      ..storedMessages.addAll(_buildMessages(count: 40));
    final chatBloc = _createChatBloc(repository);
    addTearDown(chatBloc.close);
    final connectivityCubit = ConnectivityCubit.fromStream(Stream<bool>.value(true));
    addTearDown(connectivityCubit.close);

    await tester.pumpWidget(
      MyApp(chatBloc: chatBloc, connectivityCubit: connectivityCubit),
    );
    chatBloc.add(const LoadChatHistoryEvent());
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.text('Latest'), findsOneWidget);

    chatBloc.add(
      const _EmitLoadingStateEvent(
        ChatLoaded(messages: [], isStreaming: false),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Latest'), findsNothing);
  });

  testWidgets('does not auto-scroll to bottom when user is scrolled up', (
    WidgetTester tester,
  ) async {
    final repository = _FakeChatRepository()
      ..storedMessages.addAll(_buildMessages(count: 45));
    final chatBloc = _createChatBloc(repository);
    addTearDown(chatBloc.close);
    final connectivityCubit = ConnectivityCubit.fromStream(Stream<bool>.value(true));
    addTearDown(connectivityCubit.close);

    await tester.pumpWidget(
      MyApp(chatBloc: chatBloc, connectivityCubit: connectivityCubit),
    );
    chatBloc.add(const LoadChatHistoryEvent());
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, 700));
    await tester.pumpAndSettle();

    final listViewBefore = tester.widget<ListView>(find.byType(ListView));
    final beforePixels = listViewBefore.controller!.position.pixels;
    expect(find.text('Latest'), findsOneWidget);

    final updatedMessages = _buildMessages(count: 46);
    chatBloc.add(
      _EmitLoadingStateEvent(
        ChatLoaded(messages: updatedMessages, isStreaming: true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final listViewAfter = tester.widget<ListView>(find.byType(ListView));
    final afterPixels = listViewAfter.controller!.position.pixels;
    expect((afterPixels - beforePixels).abs(), lessThan(16));
    expect(find.text('Latest'), findsOneWidget);
  });
}

List<ChatMessage> _buildMessages({required int count}) {
  final now = DateTime.now();
  return List<ChatMessage>.generate(count, (index) {
    final isUser = index.isEven;
    return ChatMessage(
      id: index + 1,
      content: isUser ? 'User message $index' : 'Assistant message $index',
      isUser: isUser,
      timestamp: now.add(Duration(seconds: index)),
    );
  });
}

class _FakeChatRepository implements ChatRepository {
  StreamController<String>? activeStreamController;
  final List<ChatMessage> storedMessages = [];
  List<ChatMessage>? lastHistoryOverride;
  bool? lastPersistUserMessage;
  int? lastResponseMessageId;

  @override
  Future<void> clearChat() async {
    storedMessages.clear();
  }

  @override
  Future<List<ChatMessage>> getChatHistory() async =>
      List<ChatMessage>.from(storedMessages)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  @override
  Stream<String> sendMessage({
    required ChatMessage userMessage,
    Uint8List? imageBytes,
    String? imageMimeType,
    List<ChatMessage>? historyOverride,
    bool persistUserMessage = true,
    int? responseMessageId,
  }) {
    lastHistoryOverride = historyOverride;
    lastPersistUserMessage = persistUserMessage;
    lastResponseMessageId = responseMessageId;
    return activeStreamController?.stream ?? Stream<String>.empty();
  }

  @override
  Future<void> saveMessage(ChatMessage message) async {
    final index = storedMessages.indexWhere((item) => item.id == message.id);
    if (index == -1) {
      storedMessages.add(message);
      return;
    }
    storedMessages[index] = message;
  }

  @override
  Future<void> deleteMessagesByIds(List<int> ids) async {
    storedMessages.removeWhere((message) => ids.contains(message.id));
  }
}

class _FakeImageStorage extends ImageStorage {
  @override
  Future<String> saveChatImage({required Uint8List bytes, String? mimeType}) async =>
      'fake_path.jpg';
}

ChatBloc _createChatBloc(_FakeChatRepository repository) {
  return _TestChatBloc(
    SendMessage(repository),
    SaveMessage(repository),
    DeleteMessagesByIds(repository),
    GetChatHistory(repository),
    ClearChat(repository),
    Stream<bool>.value(true),
    _FakeImageStorage(),
  );
}

class _TestChatBloc extends ChatBloc {
  _TestChatBloc(
    super.sendMessage,
    super.saveMessage,
    super.deleteMessagesByIds,
    super.getChatHistory,
    super.clearChat,
    super.isOnlineStream,
    super.imageStorage,
  ) {
    on<_EmitLoadingStateEvent>((event, emit) => emit(event.state));
  }
}

class _EmitLoadingStateEvent extends ChatEvent {
  const _EmitLoadingStateEvent(this.state);

  final ChatState state;
}

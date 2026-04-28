import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:jarvis/core/error/failures.dart';
import 'package:jarvis/core/storage/image_storage.dart';
import 'package:jarvis/core/utils/constants.dart';
import 'package:jarvis/features/chat/domain/entities/chat_message.dart';
import 'package:jarvis/features/chat/domain/usecases/clear_chat.dart';
import 'package:jarvis/features/chat/domain/usecases/delete_messages_by_ids.dart';
import 'package:jarvis/features/chat/domain/usecases/get_chat_history.dart';
import 'package:jarvis/features/chat/domain/usecases/save_message.dart';
import 'package:jarvis/features/chat/domain/usecases/send_message.dart';
import 'package:jarvis/features/chat/presentation/bloc/chat_event.dart';
import 'package:jarvis/features/chat/presentation/bloc/chat_state.dart';

enum _StreamTerminalState { idle, success, incomplete }

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc(
    this._sendMessage,
    this._saveMessage,
    this._deleteMessagesByIds,
    this._getChatHistory,
    this._clearChat,
    Stream<bool> isOnlineStream,
    this._imageStorage,
  ) : super(const ChatInitial()) {
    on<LoadChatHistoryEvent>(_onLoadChatHistory);
    on<ConnectivityChangedEvent>(_onConnectivityChanged);
    on<SendMessageEvent>(_onSendMessage);
    on<RetryMessageEvent>(_onRetryMessage);
    on<DeleteTurnEvent>(_onDeleteTurn);
    on<ReceiveStreamChunkEvent>(_onReceiveStreamChunk);
    on<RevealNextWordEvent>(_onRevealNextWord);
    on<StreamCompletedEvent>(_onStreamCompleted);
    on<StreamFailedEvent>(_onStreamFailed);
    on<StreamStalledEvent>(_onStreamStalled);
    on<RateLimitTickEvent>(_onRateLimitTick);
    on<ContinueAssistantResponseEvent>(_onContinueAssistantResponse);
    on<ClearChatEvent>(_onClearChat);

    _connectivitySubscription = isOnlineStream.listen(
      (isOnline) => add(ConnectivityChangedEvent(isOnline)),
    );
  }

  final SendMessage _sendMessage;
  final SaveMessage _saveMessage;
  final DeleteMessagesByIds _deleteMessagesByIds;
  final GetChatHistory _getChatHistory;
  final ClearChat _clearChat;
  final ImageStorage _imageStorage;

  StreamSubscription<String>? _streamSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _revealTimer;
  Timer? _stallTimer;
  Timer? _rateLimitTimer;
  DateTime? _rateLimitedUntil;
  bool _isOnline = true;
  int? _activeUserMessageId;
  int? _activeAssistantMessageId;
  String _pendingRevealBuffer = '';
  _StreamTerminalState _terminalState = _StreamTerminalState.idle;
  String? _terminalMessage;
  bool _hasReceivedAssistantContent = false;
  bool _hasStartedReveal = false;

  Future<void> _onClearChat(
    ClearChatEvent event,
    Emitter<ChatState> emit,
  ) async {
    final start = DateTime.now();
    emit(
      ChatLoaded(
        messages: state.messages,
        isStreaming: state.isStreaming,
        isMutating: true,
        isAwaitingServer: state.isAwaitingServer,
        hasIncompleteAssistantResponse: state.hasIncompleteAssistantResponse,
      ),
    );

    await _cancelStreamingSession();

    try {
      await _clearChat();
      await _ensureMinimumUiDuration(start);
      emit(
        const ChatLoaded(
          messages: [],
          isStreaming: false,
          isMutating: false,
          isAwaitingServer: false,
          hasIncompleteAssistantResponse: false,
        ),
      );
    } on Failure catch (failure) {
      await _ensureMinimumUiDuration(start);
      emit(
        ChatError(
          messages: state.messages,
          isStreaming: false,
          isMutating: false,
          isAwaitingServer: false,
          hasIncompleteAssistantResponse: state.hasIncompleteAssistantResponse,
          errorMessage: failure.message,
        ),
      );
    }
  }

  Future<void> _onLoadChatHistory(
    LoadChatHistoryEvent event,
    Emitter<ChatState> emit,
  ) async {
    emit(
      ChatLoading(
        messages: state.messages,
        isStreaming: false,
        isMutating: false,
        isAwaitingServer: false,
        hasIncompleteAssistantResponse: _hasIncompleteAssistant(state.messages),
      ),
    );

    try {
      final messages = await _getChatHistory();
      emit(
        ChatLoaded(
          messages: messages,
          isStreaming: false,
          isMutating: false,
          isAwaitingServer: false,
          hasIncompleteAssistantResponse: _hasIncompleteAssistant(messages),
        ),
      );
    } on Failure catch (failure) {
      emit(
        ChatError(
          messages: state.messages,
          isStreaming: false,
          isMutating: false,
          isAwaitingServer: false,
          hasIncompleteAssistantResponse: _hasIncompleteAssistant(
            state.messages,
          ),
          errorMessage: failure.message,
        ),
      );
    }
  }

  Future<void> _onConnectivityChanged(
    ConnectivityChangedEvent event,
    Emitter<ChatState> emit,
  ) async {
    _isOnline = event.isOnline;
    if (_isOnline && !state.isStreaming) {
      await _sendNextPending(emit);
    }
  }

  void _onReceiveStreamChunk(
    ReceiveStreamChunkEvent event,
    Emitter<ChatState> emit,
  ) {
    if (_activeAssistantMessageId == null || state.messages.isEmpty) {
      return;
    }

    _hasReceivedAssistantContent = true;
    _pendingRevealBuffer += event.chunk;
    _restartStallTimer();
    _scheduleRevealIfNeeded();
  }

  Future<void> _onSendMessage(
    SendMessageEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state.isStreaming) {
      return;
    }

    final rateLimitedUntil = _rateLimitedUntil;
    if (rateLimitedUntil != null && DateTime.now().isBefore(rateLimitedUntil)) {
      final remainingDuration = rateLimitedUntil.difference(DateTime.now());
      final remainingSeconds = remainingDuration.inSeconds + 1;
      _startRateLimitCountdown();
      emit(
        ChatError(
          messages: state.messages,
          isStreaming: false,
          isAwaitingServer: false,
          hasIncompleteAssistantResponse: state.hasIncompleteAssistantResponse,
          rateLimitRemaining: remainingDuration,
          errorMessage:
              'Please wait ${remainingSeconds}s before sending another message.',
        ),
      );
      return;
    }

    final trimmedText = event.text.trim();
    if (trimmedText.isEmpty && event.imageBytes == null) {
      return;
    }

    await _cancelStreamingSession();

    final now = DateTime.now();
    final imagePath = await _saveImageIfNeeded(
      imageBytes: event.imageBytes,
      imageMimeType: event.imageMimeType,
    );
    final userMessage = ChatMessage(
      id: now.microsecondsSinceEpoch,
      content: trimmedText,
      isUser: true,
      timestamp: now,
      status: _isOnline ? ChatMessageStatus.sent : ChatMessageStatus.pending,
      failureReason: _isOnline ? null : 'No internet connection.',
      imagePath: imagePath,
    );

    await _saveMessage(userMessage);

    final updatedMessages = List<ChatMessage>.from(state.messages)
      ..add(userMessage);

    if (!_isOnline) {
      emit(
        ChatLoaded(
          messages: updatedMessages,
          isStreaming: false,
          isMutating: false,
          isAwaitingServer: false,
          hasIncompleteAssistantResponse: _hasIncompleteAssistant(
            updatedMessages,
          ),
        ),
      );
      return;
    }

    final withAiPlaceholder = List<ChatMessage>.from(updatedMessages)
      ..add(
        _buildAssistantPlaceholder(
          id: now.microsecondsSinceEpoch + 1,
          timestamp: now,
        ),
      );
    emit(
      ChatStreaming(
        messages: withAiPlaceholder,
        isStreaming: true,
        isMutating: false,
        isAwaitingServer: true,
        hasIncompleteAssistantResponse: false,
      ),
    );

    await _startStreaming(
      userMessage: userMessage,
      trackedUserMessageId: userMessage.id,
      assistantMessageId: userMessage.id + 1,
      imageBytes: event.imageBytes,
      imageMimeType: event.imageMimeType,
    );
  }

  Future<void> _onRetryMessage(
    RetryMessageEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state.isStreaming) {
      return;
    }

    final message = state.messages.cast<ChatMessage?>().firstWhere(
      (m) => m?.id == event.messageId,
      orElse: () => null,
    );
    if (message == null || !message.isUser) {
      return;
    }

    if (!_isOnline) {
      final updated = _updateMessageInState(
        state.messages,
        message.copyWith(
          status: ChatMessageStatus.pending,
          failureReason: 'No internet connection.',
        ),
      );
      await _saveMessage(updated.firstWhere((m) => m.id == message.id));
      emit(
        ChatLoaded(
          messages: updated,
          isStreaming: false,
          isAwaitingServer: false,
          hasIncompleteAssistantResponse: _hasIncompleteAssistant(updated),
        ),
      );
      return;
    }

    final cleared = message.copyWith(
      status: ChatMessageStatus.sent,
      failureReason: null,
    );
    await _saveMessage(cleared);
    final updatedMessages = _updateMessageInState(state.messages, cleared);
    final withAiPlaceholder =
        _removeAssistantMessage(updatedMessages, cleared.id + 1)..add(
          _buildAssistantPlaceholder(
            id: cleared.id + 1,
            timestamp: DateTime.now(),
          ),
        );
    emit(
      ChatStreaming(
        messages: withAiPlaceholder,
        isStreaming: true,
        isMutating: false,
        isAwaitingServer: true,
        hasIncompleteAssistantResponse: false,
      ),
    );

    final (imageBytes, imageMimeType) = await _loadImageIfNeeded(
      cleared.imagePath,
    );
    await _startStreaming(
      userMessage: cleared,
      trackedUserMessageId: cleared.id,
      assistantMessageId: cleared.id + 1,
      imageBytes: imageBytes,
      imageMimeType: imageMimeType,
    );
  }

  Future<void> _onContinueAssistantResponse(
    ContinueAssistantResponseEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state.isStreaming) {
      return;
    }

    final assistantIndex = state.messages.indexWhere(
      (message) => message.id == event.assistantMessageId,
    );
    if (assistantIndex < 0 || assistantIndex != state.messages.length - 1) {
      return;
    }

    final assistantMessage = state.messages[assistantIndex];
    if (assistantMessage.isUser ||
        assistantMessage.status != ChatMessageStatus.incomplete) {
      return;
    }

    final userMessage = _findPreviousUserMessage(
      assistantIndex: assistantIndex,
      messages: state.messages,
    );
    if (userMessage == null) {
      return;
    }

    if (!_isOnline) {
      emit(
        ChatError(
          messages: state.messages,
          isStreaming: false,
          isAwaitingServer: false,
          hasIncompleteAssistantResponse: true,
          errorMessage: 'No internet connection.',
        ),
      );
      return;
    }

    await _cancelStreamingSession();

    final updatedMessages = _updateMessageInState(
      state.messages,
      assistantMessage.copyWith(
        status: ChatMessageStatus.streaming,
        failureReason: null,
      ),
    );
    emit(
      ChatStreaming(
        messages: updatedMessages,
        isStreaming: true,
        isMutating: false,
        isAwaitingServer: true,
        hasIncompleteAssistantResponse: false,
      ),
    );

    final continuePrompt = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch,
      content:
          'Continue your previous response from exactly where it stopped. Do not repeat any text that is already visible. Resume naturally from the next word.',
      isUser: true,
      timestamp: DateTime.now(),
      status: ChatMessageStatus.sent,
    );

    await _startStreaming(
      userMessage: continuePrompt,
      trackedUserMessageId: userMessage.id,
      assistantMessageId: assistantMessage.id,
      imageBytes: null,
      imageMimeType: null,
      historyOverride: [...updatedMessages, continuePrompt],
      persistUserMessage: false,
      responseMessageId: assistantMessage.id,
    );
  }

  Future<void> _onDeleteTurn(
    DeleteTurnEvent event,
    Emitter<ChatState> emit,
  ) async {
    final start = DateTime.now();
    final index = state.messages.indexWhere((m) => m.id == event.userMessageId);
    if (index < 0) {
      return;
    }

    final target = state.messages[index];
    if (!target.isUser) {
      return;
    }

    final deleteRangeEndExclusive =
        _nextUserIndexAfter(index, state.messages) ?? state.messages.length;

    final idsToDelete = state.messages
        .sublist(index, deleteRangeEndExclusive)
        .map((m) => m.id)
        .toList();

    emit(
      ChatLoaded(
        messages: state.messages,
        isStreaming: state.isStreaming,
        isMutating: true,
        isAwaitingServer: state.isAwaitingServer,
        hasIncompleteAssistantResponse: state.hasIncompleteAssistantResponse,
      ),
    );

    if (_activeUserMessageId == target.id ||
        idsToDelete.contains(_activeAssistantMessageId)) {
      await _cancelStreamingSession();
    }

    final remaining = List<ChatMessage>.from(state.messages)
      ..removeWhere((m) => idsToDelete.contains(m.id));

    try {
      await _deleteMessagesByIds(idsToDelete);
      await _ensureMinimumUiDuration(start);
    } on Failure catch (failure) {
      await _ensureMinimumUiDuration(start);
      emit(
        ChatError(
          messages: state.messages,
          isStreaming: state.isStreaming,
          isMutating: false,
          isAwaitingServer: state.isAwaitingServer,
          hasIncompleteAssistantResponse: state.hasIncompleteAssistantResponse,
          errorMessage: failure.message,
        ),
      );
      return;
    }

    emit(
      ChatLoaded(
        messages: remaining,
        isStreaming: false,
        isMutating: false,
        isAwaitingServer: false,
        hasIncompleteAssistantResponse: _hasIncompleteAssistant(remaining),
      ),
    );
  }

  Future<void> _ensureMinimumUiDuration(DateTime start) async {
    final elapsed = DateTime.now().difference(start);
    final remaining = AppConstants.minimumUiOperationDuration - elapsed;
    if (remaining.isNegative) {
      return;
    }
    await Future<void>.delayed(remaining);
  }

  int? _nextUserIndexAfter(int startIndex, List<ChatMessage> messages) {
    for (var i = startIndex + 1; i < messages.length; i++) {
      if (messages[i].isUser) {
        return i;
      }
    }
    return null;
  }

  Future<void> _sendNextPending(Emitter<ChatState> emit) async {
    final pending = state.messages
        .where((m) => m.isUser && m.status == ChatMessageStatus.pending)
        .cast<ChatMessage?>()
        .firstWhere((m) => m != null, orElse: () => null);

    if (pending == null) {
      return;
    }

    add(RetryMessageEvent(pending.id));
  }

  Future<void> _startStreaming({
    required ChatMessage userMessage,
    required int trackedUserMessageId,
    required int assistantMessageId,
    required Uint8List? imageBytes,
    required String? imageMimeType,
    List<ChatMessage>? historyOverride,
    bool persistUserMessage = true,
    int? responseMessageId,
  }) async {
    _activeUserMessageId = trackedUserMessageId;
    _activeAssistantMessageId = assistantMessageId;
    _resetStreamingRuntime();
    _restartStallTimer();

    try {
      _streamSubscription =
          _sendMessage(
            userMessage: userMessage,
            imageBytes: imageBytes,
            imageMimeType: imageMimeType,
            historyOverride: historyOverride,
            persistUserMessage: persistUserMessage,
            responseMessageId: responseMessageId,
          ).listen(
            (chunk) => add(ReceiveStreamChunkEvent(chunk)),
            onError: (Object error, StackTrace stackTrace) {
              _updateRateLimitWindow(error);
              final message = error is Failure
                  ? error.message
                  : 'Something went wrong. Please try again.';

              final activeId = _activeUserMessageId;
              add(
                StreamFailedEvent(
                  message: message,
                  userMessageId: activeId,
                  forceUserRetry: _shouldRouteFailureToUserRetry(error, message),
                ),
              );
            },
            onDone: () => add(const StreamCompletedEvent()),
            cancelOnError: true,
          );
    } on Failure catch (failure) {
      _updateRateLimitWindow(failure);
      add(
        StreamFailedEvent(
          message: failure.message,
          userMessageId: trackedUserMessageId,
          forceUserRetry: _shouldRouteFailureToUserRetry(
            failure,
            failure.message,
          ),
        ),
      );
    }
  }

  Future<String?> _saveImageIfNeeded({
    required Uint8List? imageBytes,
    required String? imageMimeType,
  }) async {
    if (imageBytes == null) {
      return null;
    }

    try {
      return await _imageStorage.saveChatImage(
        bytes: imageBytes,
        mimeType: imageMimeType,
      );
    } catch (_) {
      return null;
    }
  }

  Future<(Uint8List?, String?)> _loadImageIfNeeded(String? imagePath) async {
    if (imagePath == null || imagePath.trim().isEmpty) {
      return (null, null);
    }

    try {
      final bytes = await _imageStorage.readBytes(imagePath);
      final mimeType = _imageStorage.mimeTypeFromPath(imagePath);
      return (bytes, mimeType);
    } catch (_) {
      return (null, null);
    }
  }

  Future<void> _onRevealNextWord(
    RevealNextWordEvent event,
    Emitter<ChatState> emit,
  ) async {
    _revealTimer = null;

    final assistantId = _activeAssistantMessageId;
    if (assistantId == null) {
      return;
    }

    if (_pendingRevealBuffer.isEmpty) {
      await _completeStreamingIfReady(emit);
      return;
    }

    final nextWord = _takeNextRevealSegment();
    if (nextWord.isEmpty) {
      await _completeStreamingIfReady(emit);
      return;
    }

    _pendingRevealBuffer = _pendingRevealBuffer.substring(nextWord.length);
    _hasStartedReveal = true;

    final updatedMessages = _appendToAssistantMessage(
      state.messages,
      assistantId: assistantId,
      delta: nextWord,
    );
    emit(
      ChatStreaming(
        messages: updatedMessages,
        isStreaming: true,
        isMutating: false,
        isAwaitingServer: _terminalState == _StreamTerminalState.idle,
        hasIncompleteAssistantResponse: false,
      ),
    );

    _scheduleRevealIfNeeded();
    await _completeStreamingIfReady(emit);
  }

  Future<void> _onStreamCompleted(
    StreamCompletedEvent event,
    Emitter<ChatState> emit,
  ) async {
    _streamSubscription = null;
    _stallTimer?.cancel();
    _terminalState = _StreamTerminalState.success;
    _scheduleRevealIfNeeded(force: true);
    await _completeStreamingIfReady(emit);
  }

  Future<void> _onStreamFailed(
    StreamFailedEvent event,
    Emitter<ChatState> emit,
  ) async {
    _streamSubscription = null;
    _stallTimer?.cancel();
    final message = event.message;

    if (event.forceUserRetry) {
      await _finalizeFailedUserTurn(
        emit: emit,
        message: message,
        userMessageId: event.userMessageId,
        removeActiveAssistantMessage: true,
      );
      return;
    }

    if (_hasPartialAssistantContent()) {
      _terminalState = _StreamTerminalState.incomplete;
      _terminalMessage = message;
      _scheduleRevealIfNeeded(force: true);
      await _completeStreamingIfReady(emit);
      return;
    }

    await _finalizeFailedUserTurn(
      emit: emit,
      message: message,
      userMessageId: event.userMessageId,
    );
  }

  Future<void> _onStreamStalled(
    StreamStalledEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (!state.isStreaming || _activeAssistantMessageId == null) {
      return;
    }

    await _streamSubscription?.cancel();
    _streamSubscription = null;
    _stallTimer?.cancel();
    _terminalState = _StreamTerminalState.incomplete;
    _terminalMessage =
        'The response paused before finishing. Tap continue to resume.';
    _scheduleRevealIfNeeded(force: true);
    await _completeStreamingIfReady(emit);
  }

  List<ChatMessage> _removeEmptyTrailingAiMessage(List<ChatMessage> messages) {
    if (messages.isEmpty) {
      return messages;
    }

    final updated = List<ChatMessage>.from(messages);
    final last = updated.last;
    if (!last.isUser && last.content.trim().isEmpty) {
      updated.removeLast();
    }
    return updated;
  }

  List<ChatMessage> _updateMessageInState(
    List<ChatMessage> messages,
    ChatMessage updatedMessage,
  ) {
    return messages
        .map((m) => m.id == updatedMessage.id ? updatedMessage : m)
        .toList();
  }

  void _updateRateLimitWindow(Object error) {
    if (error case RateLimitFailure(:final retryAfter)) {
      _rateLimitedUntil = DateTime.now().add(
        retryAfter ?? const Duration(seconds: 30),
      );
      _startRateLimitCountdown();
    }
  }

  @override
  Future<void> close() async {
    await _cancelStreamingSession();
    _rateLimitTimer?.cancel();
    await _connectivitySubscription?.cancel();
    return super.close();
  }

  void _onRateLimitTick(
    RateLimitTickEvent event,
    Emitter<ChatState> emit,
  ) {
    final remaining = event.remaining;
    if (remaining == null || remaining <= Duration.zero) {
      _rateLimitTimer?.cancel();
      _rateLimitTimer = null;
      _rateLimitedUntil = null;
    }

    emit(
      ChatLoaded(
        messages: state.messages,
        isStreaming: state.isStreaming,
        isMutating: state.isMutating,
        isAwaitingServer: state.isAwaitingServer,
        hasIncompleteAssistantResponse: state.hasIncompleteAssistantResponse,
        rateLimitRemaining:
            remaining == null || remaining <= Duration.zero ? null : remaining,
      ),
    );
  }

  void _startRateLimitCountdown() {
    final until = _rateLimitedUntil;
    if (until == null) {
      return;
    }

    _rateLimitTimer?.cancel();
    _rateLimitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (isClosed) {
        timer.cancel();
        return;
      }

      final remaining = until.difference(DateTime.now());
      add(RateLimitTickEvent(remaining));
      if (remaining <= Duration.zero) {
        timer.cancel();
      }
    });
  }

  ChatMessage _buildAssistantPlaceholder({
    required int id,
    required DateTime timestamp,
  }) {
    return ChatMessage(
      id: id,
      content: '',
      isUser: false,
      timestamp: timestamp,
      status: ChatMessageStatus.streaming,
    );
  }

  Future<void> _cancelStreamingSession() async {
    _revealTimer?.cancel();
    _revealTimer = null;
    _stallTimer?.cancel();
    _stallTimer = null;
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    _activeUserMessageId = null;
    _activeAssistantMessageId = null;
    _resetStreamingRuntime();
  }

  void _resetStreamingRuntime() {
    _pendingRevealBuffer = '';
    _terminalState = _StreamTerminalState.idle;
    _terminalMessage = null;
    _hasReceivedAssistantContent = false;
    _hasStartedReveal = false;
  }

  void _restartStallTimer() {
    _stallTimer?.cancel();
    if (_terminalState != _StreamTerminalState.idle) {
      return;
    }
    _stallTimer = Timer(AppConstants.assistantStreamStallTimeout, () {
      if (!isClosed) {
        add(const StreamStalledEvent());
      }
    });
  }

  bool _hasMinimumRevealBuffer() {
    return _countWords(_pendingRevealBuffer) >=
        AppConstants.assistantInitialRevealWordBuffer;
  }

  void _scheduleRevealIfNeeded({bool force = false}) {
    if (_activeAssistantMessageId == null || _revealTimer != null) {
      return;
    }
    if (_pendingRevealBuffer.isEmpty) {
      return;
    }
    if (!force &&
        !_hasStartedReveal &&
        _terminalState == _StreamTerminalState.idle &&
        !_hasMinimumRevealBuffer()) {
      return;
    }
    _revealTimer = Timer(AppConstants.assistantWordRevealDelay, () {
      if (!isClosed) {
        add(const RevealNextWordEvent());
      }
    });
  }

  int _countWords(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return 0;
    }
    return RegExp(r'\S+').allMatches(trimmed).length;
  }

  String _takeNextRevealSegment() {
    final match = RegExp(r'^\s*\S+\s*').stringMatch(_pendingRevealBuffer);
    return match ?? _pendingRevealBuffer;
  }

  List<ChatMessage> _appendToAssistantMessage(
    List<ChatMessage> messages, {
    required int assistantId,
    required String delta,
  }) {
    return messages.map((message) {
      if (message.id != assistantId) {
        return message;
      }
      return message.copyWith(
        content: message.content + delta,
        status: ChatMessageStatus.streaming,
        failureReason: null,
      );
    }).toList();
  }

  bool _hasPartialAssistantContent() {
    if (_hasReceivedAssistantContent ||
        _pendingRevealBuffer.trim().isNotEmpty) {
      return true;
    }

    final assistantId = _activeAssistantMessageId;
    if (assistantId == null) {
      return false;
    }

    final assistant = state.messages.cast<ChatMessage?>().firstWhere(
      (message) => message?.id == assistantId,
      orElse: () => null,
    );
    return assistant != null && assistant.content.trim().isNotEmpty;
  }

  Future<void> _completeStreamingIfReady(Emitter<ChatState> emit) async {
    if (_activeAssistantMessageId == null || _revealTimer != null) {
      return;
    }
    if (_pendingRevealBuffer.isNotEmpty) {
      _scheduleRevealIfNeeded(
        force: _terminalState != _StreamTerminalState.idle,
      );
      return;
    }

    switch (_terminalState) {
      case _StreamTerminalState.idle:
        return;
      case _StreamTerminalState.success:
        await _finalizeAssistantMessage(
          emit: emit,
          status: ChatMessageStatus.sent,
          errorMessage: null,
        );
        return;
      case _StreamTerminalState.incomplete:
        await _finalizeAssistantMessage(
          emit: emit,
          status: ChatMessageStatus.incomplete,
          errorMessage: _terminalMessage,
        );
        return;
    }
  }

  Future<void> _finalizeAssistantMessage({
    required Emitter<ChatState> emit,
    required ChatMessageStatus status,
    required String? errorMessage,
  }) async {
    final assistantId = _activeAssistantMessageId;
    if (assistantId == null) {
      return;
    }

    final cleanedMessages = _removeEmptyTrailingAiMessage(state.messages);
    final assistantIndex = cleanedMessages.indexWhere(
      (m) => m.id == assistantId,
    );

    List<ChatMessage> finalMessages;
    if (assistantIndex < 0) {
      finalMessages = cleanedMessages;
    } else {
      final assistant = cleanedMessages[assistantIndex].copyWith(
        status: status,
        failureReason: errorMessage,
      );
      if (assistant.content.trim().isNotEmpty) {
        await _saveMessage(assistant);
      }
      finalMessages = _updateMessageInState(cleanedMessages, assistant);
    }

    _activeUserMessageId = null;
    _activeAssistantMessageId = null;
    _resetStreamingRuntime();

    emit(
      ChatLoaded(
        messages: finalMessages,
        isStreaming: false,
        isMutating: false,
        isAwaitingServer: false,
        hasIncompleteAssistantResponse: _hasIncompleteAssistant(finalMessages),
        errorMessage: errorMessage,
      ),
    );
  }

  Future<void> _finalizeFailedUserTurn({
    required Emitter<ChatState> emit,
    required String message,
    required int? userMessageId,
    bool removeActiveAssistantMessage = false,
  }) async {
    _activeUserMessageId = null;
    final assistantMessageId = _activeAssistantMessageId;
    _activeAssistantMessageId = null;
    _resetStreamingRuntime();

    var cleaned = _removeEmptyTrailingAiMessage(state.messages);
    if (removeActiveAssistantMessage && assistantMessageId != null) {
      cleaned = _removeAssistantMessage(cleaned, assistantMessageId);
    }
    final targetId = userMessageId;
    if (targetId != null) {
      final idx = cleaned.indexWhere((m) => m.id == targetId);
      if (idx >= 0) {
        final userFacingMessage = _userFacingFailedUserMessage(message);
        final failedUser = cleaned[idx].copyWith(
          status: ChatMessageStatus.failed,
          failureReason: userFacingMessage,
        );
        await _saveMessage(failedUser);
        final updatedMessages = _updateMessageInState(cleaned, failedUser);
        emit(
          ChatError(
            messages: updatedMessages,
            isStreaming: false,
            isMutating: false,
            isAwaitingServer: false,
            hasIncompleteAssistantResponse: _hasIncompleteAssistant(
              updatedMessages,
            ),
            errorMessage: userFacingMessage,
          ),
        );
        return;
      }
    }

    emit(
      ChatError(
        messages: cleaned,
        isStreaming: false,
        isMutating: false,
        isAwaitingServer: false,
        hasIncompleteAssistantResponse: _hasIncompleteAssistant(cleaned),
        errorMessage: _userFacingFailedUserMessage(message),
      ),
    );
  }

  bool _hasIncompleteAssistant(List<ChatMessage> messages) {
    return messages.any(
      (message) =>
          !message.isUser && message.status == ChatMessageStatus.incomplete,
    );
  }

  List<ChatMessage> _removeAssistantMessage(
    List<ChatMessage> messages,
    int assistantMessageId,
  ) {
    return List<ChatMessage>.from(messages)
      ..removeWhere((message) => message.id == assistantMessageId);
  }

  ChatMessage? _findPreviousUserMessage({
    required int assistantIndex,
    required List<ChatMessage> messages,
  }) {
    for (var i = assistantIndex - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.isUser) {
        return message;
      }
    }
    return null;
  }

  bool _shouldRouteFailureToUserRetry(Object error, String message) {
    if (error is ServerFailure) {
      return true;
    }

    final normalized = message.trim().toLowerCase();
    return normalized.contains('service unavailable') ||
        normalized.contains('server failure');
  }

  String _userFacingFailedUserMessage(String message) {
    final normalized = message.trim().toLowerCase();
    if (normalized.contains('service unavailable') ||
        normalized.contains('server failure')) {
      return 'Server unavailable. Tap to retry.';
    }
    return message;
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:jarvis/core/network/connectivity_cubit.dart';
import 'package:jarvis/core/utils/constants.dart';
import 'package:jarvis/features/chat/domain/entities/chat_message.dart';
import 'package:jarvis/features/chat/presentation/bloc/chat_bloc.dart';
import 'package:jarvis/features/chat/presentation/bloc/chat_event.dart';
import 'package:jarvis/features/chat/presentation/bloc/chat_state.dart';
import 'package:jarvis/features/chat/presentation/widgets/chat_bubble.dart';
import 'package:jarvis/features/chat/presentation/widgets/chat_history_loading_view.dart';
import 'package:jarvis/features/chat/presentation/widgets/message_input.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ScrollController _scrollController = ScrollController();
  bool _hasSeenConnectivityEvent = false;
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollChanged);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<ChatBloc, ChatState>(
          listenWhen: (previous, current) =>
              previous.messages != current.messages ||
              previous.isStreaming != current.isStreaming ||
              previous.errorMessage != current.errorMessage,
          listener: (context, state) {
            _scheduleScrollToBottom(state);

            final errorMessage = state.errorMessage;
            if (errorMessage != null && errorMessage.isNotEmpty) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(errorMessage)));
            }
          },
        ),
        BlocListener<ConnectivityCubit, bool>(
          listenWhen: (previous, current) => previous != current,
          listener: (context, isOnline) {
            // On initial value: show only if we're offline (like Chrome).
            if (!_hasSeenConnectivityEvent) {
              _hasSeenConnectivityEvent = true;
              if (!isOnline) {
                _showConnectivitySnackBar(isOnline: false);
              }
              return;
            }

            _showConnectivitySnackBar(isOnline: isOnline);
          },
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: const Text(AppConstants.appTitle),
          actions: [
            IconButton(
              onPressed: () =>
                  context.read<ChatBloc>().add(const ClearChatEvent()),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear chat',
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: BlocBuilder<ChatBloc, ChatState>(
                    buildWhen: (previous, current) =>
                        previous.messages != current.messages ||
                        previous.isStreaming != current.isStreaming ||
                        previous.runtimeType != current.runtimeType,
                    builder: (context, state) {
                      if (state is ChatLoading) {
                        return const ChatHistoryLoadingView();
                      }

                      final messages = state.messages;
                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length + 1,
                        itemBuilder: (context, index) {
                          if (index == messages.length) {
                            return const _TypingIndicator();
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _ChatMessageItem(index: index),
                          );
                        },
                      );
                    },
                  ),
                ),
                BlocSelector<ChatBloc, ChatState, bool>(
                  selector: (state) => state.isStreaming,
                  builder: (context, isStreaming) {
                    return MessageInput(
                      isStreaming: isStreaming,
                      rateLimitRemaining: context.select(
                        (ChatBloc bloc) => bloc.state.rateLimitRemaining,
                      ),
                      onSend:
                          (
                            String text,
                            Uint8List? imageBytes,
                            String? imageMimeType,
                          ) {
                            context.read<ChatBloc>().add(
                              SendMessageEvent(
                                text: text,
                                imageBytes: imageBytes,
                                imageMimeType: imageMimeType,
                              ),
                            );
                          },
                    );
                  },
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 140,
              child: IgnorePointer(
                ignoring: !_showScrollToBottom,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: !_showScrollToBottom
                      ? const SizedBox.shrink()
                      : Center(
                          child: Material(
                            key: const ValueKey('scroll_to_bottom_chip'),
                            elevation: 3,
                            color: Theme.of(context).colorScheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: InkWell(
                              onTap: _scrollToBottom,
                              borderRadius: BorderRadius.circular(18),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.keyboard_arrow_down,
                                      size: 20,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Latest',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelLarge,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            BlocSelector<ChatBloc, ChatState, bool>(
              selector: (state) => state.isMutating,
              builder: (context, isMutating) {
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: !isMutating
                      ? const SizedBox.shrink()
                      : const _MutationOverlay(
                          key: ValueKey('mutation_overlay'),
                        ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _scheduleScrollToBottom(ChatState state) {
    if (state.messages.isEmpty) {
      _handleEmptyMessagesState();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      if (!_isNearBottom() && !_isAtInitialListPosition()) {
        return;
      }

      _scrollToBottom();
    });
  }

  void _handleEmptyMessagesState() {
    if (_showScrollToBottom && mounted) {
      setState(() => _showScrollToBottom = false);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      final minExtent = _scrollController.position.minScrollExtent;
      if ((_scrollController.position.pixels - minExtent).abs() > 0.5) {
        _scrollController.jumpTo(minExtent);
      }
    });
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) {
      return true;
    }
    const nearBottomThreshold = 80.0;
    final position = _scrollController.position;
    final distanceFromBottom = position.maxScrollExtent - position.pixels;
    return distanceFromBottom <= nearBottomThreshold;
  }

  bool _isAtInitialListPosition() {
    if (!_scrollController.hasClients) {
      return true;
    }
    final minExtent = _scrollController.position.minScrollExtent;
    return (_scrollController.position.pixels - minExtent).abs() <= 2;
  }

  Future<void> _scrollToBottom() async {
    if (!_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    final targetExtent = position.maxScrollExtent;
    final distanceFromBottom = targetExtent - position.pixels;
    if (distanceFromBottom <= 0) {
      return;
    }

    final duration = _scrollAnimationDuration(distanceFromBottom);
    await _scrollController.animateTo(
      targetExtent,
      duration: duration,
      curve: Curves.easeInOutCubicEmphasized,
    );

    if (!mounted || !_scrollController.hasClients) {
      return;
    }

    // If extent changed during animation (streaming/layout), finalize instantly
    // to avoid a visible second animated "jump".
    final finalMaxExtent = _scrollController.position.maxScrollExtent;
    final remaining = finalMaxExtent - _scrollController.position.pixels;
    if (remaining > 8) {
      _scrollController.jumpTo(finalMaxExtent);
    }
  }

  Duration _scrollAnimationDuration(double distanceFromBottom) {
    final ms = (220 + distanceFromBottom * 0.18).round().clamp(220, 900);
    return Duration(milliseconds: ms);
  }

  void _onScrollChanged() {
    if (!_scrollController.hasClients) {
      return;
    }

    final hasMessages = context.read<ChatBloc>().state.messages.isNotEmpty;
    if (!hasMessages) {
      if (_showScrollToBottom && mounted) {
        setState(() => _showScrollToBottom = false);
      }
      return;
    }

    // WhatsApp-like behavior: show button only when user is meaningfully away
    // from the bottom (latest message).
    const threshold = 220.0;
    final distanceFromBottom =
        _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    final shouldShow = distanceFromBottom > threshold;

    if (shouldShow != _showScrollToBottom && mounted) {
      setState(() => _showScrollToBottom = shouldShow);
    }
  }

  void _showConnectivitySnackBar({required bool isOnline}) {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final background = isOnline
        ? scheme.primaryContainer
        : scheme.errorContainer;
    final foreground = isOnline
        ? scheme.onPrimaryContainer
        : scheme.onErrorContainer;
    final icon = isOnline ? Icons.wifi : Icons.wifi_off;
    final text = isOnline ? 'Back online' : 'You are currently offline';

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: background,
          duration: isOnline
              ? const Duration(seconds: 2)
              : const Duration(days: 1),
          content: Row(
            children: [
              Icon(icon, color: foreground),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
          action: isOnline
              ? null
              : SnackBarAction(
                  label: 'DISMISS',
                  textColor: foreground,
                  onPressed: () => messenger.hideCurrentSnackBar(),
                ),
        ),
      );
  }
}

class _ChatMessageItem extends StatelessWidget {
  const _ChatMessageItem({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      buildWhen: (previous, current) =>
          previous.messages.length != current.messages.length ||
          index < current.messages.length &&
              index < previous.messages.length &&
              previous.messages[index] != current.messages[index],
      builder: (context, state) {
        if (index >= state.messages.length) {
          return const SizedBox.shrink();
        }

        final message = state.messages[index];
        final canContinueAssistant =
            !message.isUser &&
            message.status == ChatMessageStatus.incomplete &&
            !state.isStreaming &&
            index == state.messages.length - 1;
        return Align(
          alignment: message.isUser
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: _MessageActionsWrapper(
            message: message,
            child: _RetryWrapper(
              message: message,
              child: ChatBubble(
                key: ValueKey(message.id),
                message: message,
                onContinue: !canContinueAssistant
                    ? null
                    : () => context.read<ChatBloc>().add(
                        ContinueAssistantResponseEvent(message.id),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MessageActionsWrapper extends StatelessWidget {
  const _MessageActionsWrapper({required this.message, required this.child});

  final ChatMessage message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!message.isUser) {
      return child;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onLongPress: () => _showUserMessageSheet(context, message),
      child: child,
    );
  }

  Future<void> _showUserMessageSheet(
    BuildContext context,
    ChatMessage message,
  ) async {
    final action = await showModalBottomSheet<_UserMessageAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete'),
                onTap: () =>
                    Navigator.of(context).pop(_UserMessageAction.delete),
              ),
            ],
          ),
        );
      },
    );

    if (action == null) {
      return;
    }

    switch (action) {
      case _UserMessageAction.delete:
        if (context.mounted) {
          context.read<ChatBloc>().add(DeleteTurnEvent(message.id));
        }
    }
  }
}

enum _UserMessageAction { delete }

class _RetryWrapper extends StatelessWidget {
  const _RetryWrapper({required this.message, required this.child});

  final ChatMessage message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // User messages only: tap-to-retry on failed.
    if (message.isUser == true && message.status == ChatMessageStatus.failed) {
      return InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () =>
            context.read<ChatBloc>().add(RetryMessageEvent(message.id)),
        child: child,
      );
    }

    return child;
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<ChatBloc, ChatState, bool>(
      selector: (state) => state.isStreaming,
      builder: (context, isStreaming) {
        if (!isStreaming) {
          return const SizedBox.shrink();
        }

        return const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 12),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text('JARVIS is typing...'),
            ],
          ),
        );
      },
    );
  }
}

class _MutationOverlay extends StatelessWidget {
  const _MutationOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black45,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Updating chat…',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

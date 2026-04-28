import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:jarvis/features/chat/domain/entities/chat_message.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    required this.message,
    this.onContinue,
    super.key,
  });

  final ChatMessage message;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final alignment =
        message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleColor = message.isUser
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = message.isUser
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;
    final secondaryTextColor = message.isUser
        ? Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.75)
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: alignment,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.76,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (message.isUser && message.imagePath != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(
                          File(message.imagePath!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  if (!message.isUser && message.content.trim().isNotEmpty)
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Copy response',
                        onPressed: () => _copyResponse(context),
                        icon: const Icon(Icons.copy_all_outlined, size: 18),
                      ),
                    ),
                  if (message.isUser)
                    Text(
                      message.content,
                      textAlign: TextAlign.start,
                      softWrap: true,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: textColor,
                        height: 1.4,
                      ),
                    )
                  else
                    MarkdownBody(
                      data: message.content,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                          .copyWith(
                            p: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                            ),
                            blockSpacing: 10,
                            listIndent: 20,
                            codeblockPadding: const EdgeInsets.all(12),
                          ),
                    ),
                  if (!message.isUser &&
                      message.status == ChatMessageStatus.incomplete) ...[
                    const SizedBox(height: 10),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message.failureReason?.trim().isNotEmpty == true
                                  ? message.failureReason!
                                  : 'The response stopped before finishing.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (onContinue != null) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: onContinue,
                                  child: const Text('Continue response'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (message.isUser) ...[
                    const SizedBox(height: 6),
                    _StatusRow(
                      status: message.status,
                      color: secondaryTextColor,
                      failureReason: message.failureReason,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _copyResponse(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Response copied'),
          duration: Duration(seconds: 2),
        ),
      );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.status,
    required this.color,
    required this.failureReason,
  });

  final ChatMessageStatus status;
  final Color color;
  final String? failureReason;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (status) {
      ChatMessageStatus.pending => (Icons.schedule, 'Pending'),
      ChatMessageStatus.failed => (Icons.error_outline, 'Failed'),
      ChatMessageStatus.streaming => (Icons.more_horiz, 'Sending'),
      ChatMessageStatus.incomplete => (Icons.pause_circle_outline, 'Incomplete'),
      ChatMessageStatus.sent => (Icons.check, 'Sent'),
    };

    final extra = status == ChatMessageStatus.failed &&
            failureReason != null &&
            failureReason!.trim().isNotEmpty
        ? ' • ${failureReason!.trim()}'
        : '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '$label$extra',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

class ChatHistoryLoadingView extends StatelessWidget {
  const ChatHistoryLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();

    return Skeletonizer(
      enabled: true,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 8,
        itemBuilder: (context, index) {
          final isUser = index.isEven;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Align(
              alignment:
                  isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.8,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isUser
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isUser
                              ? 'Loading previous message $index'
                              : 'Restoring conversation content from local storage for a longer answer preview.',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          MaterialLocalizations.of(
                            context,
                          ).formatTimeOfDay(
                            TimeOfDay.fromDateTime(
                              now.add(Duration(minutes: index)),
                            ),
                          ),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

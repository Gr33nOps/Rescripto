import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/icon_catalog.dart';
import '../models/history_entry.dart';
import '../services/config_store.dart';
import '../state/history_controller.dart';
import 'history_detail_screen.dart';

/// Local rewrite history.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HistoryController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (controller.entries.isNotEmpty)
            Semantics(
              identifier: 'history_clear_all',
              child: IconButton(
                tooltip: 'Clear all',
                onPressed: () => _confirmClear(context),
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: controller.loading
            ? const Center(child: CircularProgressIndicator())
            : controller.isEmpty && controller.error != null
            ? _HistoryError(
                message: controller.error!,
                onRetry: controller.refresh,
              )
            : controller.isEmpty
            ? _EmptyHistory()
            : _HistoryList(controller: controller),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all history?'),
        content: const Text(
          'This deletes every saved rewrite from this device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          Semantics(
            identifier: 'history_clear_confirm',
            child: FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete all'),
            ),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<HistoryController>().clear();
    }
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.controller});

  final HistoryController controller;

  @override
  Widget build(BuildContext context) {
    final errorOffset = controller.error == null ? 0 : 1;
    // Hide the pager while an error is showing: the error card shifts every
    // row down by one, which would rebuild the sentinel and retry the very
    // query that just failed, in a loop. Recovery goes through Retry instead.
    final showPager = controller.hasMore && controller.error == null;

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: errorOffset + controller.entries.length + (showPager ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (errorOffset == 1 && index == 0) {
            return _HistoryErrorCard(
              message: controller.error!,
              onRetry: controller.refresh,
            );
          }
          final entryIndex = index - errorOffset;
          if (entryIndex >= controller.entries.length) {
            return const _PagerTile();
          }
          return _HistoryCard(entry: controller.entries[entryIndex]);
        },
      ),
    );
  }
}

/// Trailing sentinel that pages in the next batch once it scrolls into view.
class _PagerTile extends StatefulWidget {
  const _PagerTile();

  @override
  State<_PagerTile> createState() => _PagerTileState();
}

class _PagerTileState extends State<_PagerTile> {
  @override
  void initState() {
    super.initState();
    // Building this tile means the list reached the end of what is loaded.
    // Defer past the current frame so the fetch does not notify listeners
    // while the list that triggered it is still laying out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<HistoryController>().loadMore();
    });
  }

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 20),
    child: Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      ),
    ),
  );
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final tone = context.watch<ConfigStore>().toneById(entry.toneId);
    final scheme = Theme.of(context).colorScheme;
    final date = DateFormat('MMM d, HH:mm').format(entry.createdAt);

    return Semantics(
      identifier: 'history_item_${entry.id}',
      child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => HistoryDetailScreen(entry: entry)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              IconCatalog.resolve(tone.iconToken),
                              size: 18,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                tone.name,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: scheme.primary,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          date,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    identifier: 'history_item_delete_${entry.id}',
                    child: IconButton(
                      tooltip: 'Delete',
                      onPressed: () =>
                          context.read<HistoryController>().delete(entry.id),
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _snippet(context, 'Original', entry.original, scheme, faded: true),
              const SizedBox(height: 6),
              _snippet(context, 'Rewrite', entry.rewritten, scheme),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _snippet(
    BuildContext context,
    String label,
    String text,
    ColorScheme scheme, {
    bool faded = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            height: 1.4,
            color: faded ? scheme.onSurfaceVariant : scheme.onSurface,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: const Alignment(0, -0.18),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 64, color: scheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              'No rewrites yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Completed rewrites will appear here and stay on this device.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryError extends StatelessWidget {
  const _HistoryError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Semantics(
              identifier: 'history_retry',
              child: FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryErrorCard extends StatelessWidget {
  const _HistoryErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

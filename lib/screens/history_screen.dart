import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/history_entry.dart';
import '../models/tone_preset.dart';
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
            IconButton(
              tooltip: 'Clear all',
              onPressed: () => _confirmClear(context),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: controller.loading
            ? const Center(child: CircularProgressIndicator())
            : controller.isEmpty
                ? _EmptyHistory()
                : RefreshIndicator(
                    onRefresh: controller.refresh,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: controller.entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final entry = controller.entries[index];
                        return _HistoryCard(entry: entry);
                      },
                    ),
                  ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all history?'),
        content: const Text(
            'This deletes every saved rewrite from this device. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<HistoryController>().clear();
    }
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final tone = ToneLibrary.byId(entry.toneId);
    final scheme = Theme.of(context).colorScheme;
    final date = DateFormat('MMM d, HH:mm').format(entry.createdAt);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HistoryDetailScreen(entry: entry),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(tone.icon, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    tone.name,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    date,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: () =>
                        context.read<HistoryController>().delete(entry.id),
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _snippet(entry.original, scheme, faded: true),
              const SizedBox(height: 6),
              _snippet(entry.rewritten, scheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _snippet(String text, ColorScheme scheme, {bool faded = false}) {
    return Text(
      text,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        height: 1.4,
        color: faded ? scheme.onSurfaceVariant : scheme.onSurface,
        fontSize: 13,
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 64, color: scheme.outlineVariant),
          const SizedBox(height: 16),
          Text('No rewrites yet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Your rewrites are saved here, only on this device.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_messenger.dart';
import '../core/icon_catalog.dart';
import '../models/history_entry.dart';
import '../services/config_store.dart';

/// Full view of one saved rewrite.
class HistoryDetailScreen extends StatelessWidget {
  const HistoryDetailScreen({super.key, required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final tone = context.watch<ConfigStore>().toneById(entry.toneId);
    final date = DateFormat.yMMMd().add_jm().format(entry.createdAt);

    return Scaffold(
      appBar: AppBar(title: Text(tone.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _block(
              context,
              title: 'Original',
              icon: Icons.edit_outlined,
              text: entry.original,
            ),
            const SizedBox(height: 16),
            _block(
              context,
              title: 'Rewrite',
              icon: Icons.auto_fix_high,
              text: entry.rewritten,
              highlighted: true,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(IconCatalog.resolve(tone.iconToken), size: 16),
                  label: Text(tone.name),
                ),
                if (entry.intensityLabel != null)
                  Chip(label: Text(entry.intensityLabel!)),
                if (entry.lengthLabel != null)
                  Chip(label: Text('Length: ${entry.lengthLabel}')),
                Chip(
                  avatar: const Icon(Icons.calendar_today_outlined, size: 14),
                  label: Text(date),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    identifier: 'history_detail_copy',
                    child: OutlinedButton.icon(
                      onPressed: () => _copy(context, entry.rewritten),
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Copy'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    identifier: 'history_detail_share',
                    child: FilledButton.icon(
                      onPressed: () => SharePlus.instance.share(
                        ShareParams(
                          text: entry.rewritten,
                          subject: 'Rewritten with Rescripto',
                        ),
                      ),
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Share'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _block(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String text,
    bool highlighted = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.primaryContainer
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    showAppSnackBar('Copied to clipboard');
  }
}

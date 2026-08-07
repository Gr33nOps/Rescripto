import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ai_model.dart';
import '../services/model_manager.dart';
import '../state/models_controller.dart';

/// Model manager: download / select / delete on-device GGUF models.
class ModelsScreen extends StatelessWidget {
  const ModelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ModelsController>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('AI Models')),
      body: SafeArea(
        child: controller.scanning
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline, color: scheme.onSecondaryContainer),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Models download once, then everything runs on your '
                            'phone. No cloud, no accounts, no data leaves the device.',
                            style: TextStyle(color: scheme.onSecondaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final model in controller.catalog) ...[
                    _ModelTile(
                      model: model,
                      installed: controller.isInstalled(model.id),
                      selected: controller.selectedModelId == model.id,
                      progress: controller.progressFor(model.id),
                      onSelect: () => controller.selectModel(model),
                      onDownload: () => controller.download(model),
                      onCancel: () => controller.cancelDownload(model),
                      onDelete: () => controller.deleteModel(model),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.installed,
    required this.selected,
    required this.progress,
    required this.onSelect,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
  });

  final AiModel model;
  final bool installed;
  final bool selected;
  final DownloadProgress? progress;
  final VoidCallback onSelect;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prog = progress;
    final downloading = prog != null && prog.isRunning;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(model.familyIcon,
                      size: 20, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              model.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (model.isDefault) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: scheme.tertiaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Recommended',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: scheme.onTertiaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${model.parameters} · ${model.quant} · ${_mb(model.sizeMb)} · '
                        '${model.languages.join(', ')}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (downloading) ...[
              _DownloadProgress(progress: prog),
            ] else if (installed) ...[
              Row(
                children: [
                  if (selected)
                    const Chip(
                      avatar: Icon(Icons.check_circle, size: 16),
                      label: Text('Active'),
                    )
                  else
                    OutlinedButton(
                      onPressed: onSelect,
                      child: const Text('Use this model'),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Delete from device',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download_outlined),
                  label: Text('Download · ${_mb(model.sizeMb)}'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _mb(int sizeMb) {
    if (sizeMb >= 1024) return '${(sizeMb / 1024).toStringAsFixed(1)} GB';
    return '$sizeMb MB';
  }
}

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({required this.progress});

  final DownloadProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = (progress.fraction * 100).clamp(0, 100).toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'Downloading… ${_mb(progress.receivedMb)} / '
              '${_mb(progress.totalMb)} ($pct%)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Cancel',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  context.read<ModelsController>().cancelDownload(
                        ModelCatalog.models.firstWhere(
                          (m) => m.id == progress.modelId,
                        ),
                      ),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress.fraction,
            minHeight: 6,
            backgroundColor: scheme.surfaceContainerHigh,
          ),
        ),
      ],
    );
  }

  String _mb(double mb) {
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }
}

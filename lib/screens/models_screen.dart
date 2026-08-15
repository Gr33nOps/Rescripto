import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ai_model.dart';
import '../services/model_manager.dart';
import '../state/models_controller.dart';
import '../state/rewrite_controller.dart';

/// Model manager: download / select / delete on-device GGUF models.
class ModelsScreen extends StatelessWidget {
  const ModelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ModelsController>();
    final rewrite = context.watch<RewriteController>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('On-device models')),
      body: SafeArea(
        child: controller.scanning
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 104),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          color: scheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Download one model to rewrite privately, even when '
                            'you are offline.',
                            style: TextStyle(
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (controller.error != null) ...[
                    _ErrorBanner(message: controller.error!),
                    const SizedBox(height: 12),
                  ],
                  for (final model in controller.catalog) ...[
                    _ModelTile(
                      model: model,
                      installed: controller.isInstalled(model.id),
                      selected: controller.selectedModelId == model.id,
                      progress: controller.progressFor(model.id),
                      downloadBlocked:
                          controller.hasActiveDownload &&
                          controller.activeDownloadId != model.id,
                      deleteBlocked: rewrite.isRunning,
                      onSelect: () => controller.selectModel(model),
                      onDownload: () => controller.download(model),
                      onCancel: () => controller.cancelDownload(model),
                      onDelete: () =>
                          _confirmDelete(context, controller, model),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ModelsController controller,
    AiModel model,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${model.name}?'),
        content: Text(
          controller.selectedModelId == model.id
              ? 'This is the active model. It will be unloaded and you will need '
                    'an installed model before rewriting again.'
              : 'The downloaded model file will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.deleteModel(model);
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.installed,
    required this.selected,
    required this.progress,
    required this.downloadBlocked,
    required this.deleteBlocked,
    required this.onSelect,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
  });

  final AiModel model;
  final bool installed;
  final bool selected;
  final DownloadProgress? progress;
  final bool downloadBlocked;
  final bool deleteBlocked;
  final VoidCallback onSelect;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prog = progress;
    final downloading = prog != null && prog.isRunning;
    final failed = prog?.status == DownloadStatus.failed;

    return Semantics(
      container: true,
      identifier: 'model_tile_${model.id}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(
                      model.familyIcon,
                      size: 20,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              model.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (model.isDefault) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Recommended',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: scheme.onPrimary,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.2,
                                      ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_descriptor(model)} · ${_mb(model.sizeMb)} · ${model.languages.join(', ')}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${model.parameters} · ${model.quant}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (downloading) ...[
                _DownloadProgress(progress: prog),
              ] else if (failed) ...[
                Text(
                  prog?.error ?? 'Download failed.',
                  style: TextStyle(color: scheme.error),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: Semantics(
                    identifier: 'model_retry_${model.id}',
                    child: FilledButton.tonalIcon(
                      onPressed: downloadBlocked ? null : onDownload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry download'),
                    ),
                  ),
                ),
              ] else if (installed) ...[
                Row(
                  children: [
                    if (selected)
                      const Chip(
                        avatar: Icon(Icons.check_circle, size: 16),
                        label: Text('Active'),
                      )
                    else
                      Semantics(
                        identifier: 'model_select_${model.id}',
                        child: OutlinedButton(
                          onPressed: onSelect,
                          child: const Text('Use model'),
                        ),
                      ),
                    const Spacer(),
                    Semantics(
                      identifier: 'model_delete_${model.id}',
                      child: IconButton(
                        tooltip: deleteBlocked
                            ? 'Stop the current rewrite before deleting models'
                            : 'Delete from device',
                        onPressed: deleteBlocked ? null : onDelete,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    identifier: 'model_download_${model.id}',
                    child: OutlinedButton.icon(
                      onPressed: downloadBlocked ? null : onDownload,
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: Text(
                        downloadBlocked
                            ? 'Finish current download'
                            : 'Download',
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _mb(int sizeMb) {
    if (sizeMb >= 1024) return '${(sizeMb / 1024).toStringAsFixed(1)} GB';
    return '$sizeMb MB';
  }

  String _descriptor(AiModel model) {
    if (model.sizeMb <= 900) return 'Fast · works well on most phones';
    if (model.sizeMb >= 2500) return 'Highest quality · needs more memory';
    return 'Balanced quality and speed';
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

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
          ],
        ),
      ),
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({required this.progress});

  final DownloadProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = (progress.fraction * 100).clamp(0, 100).toStringAsFixed(0);
    final verifying = progress.status == DownloadStatus.verifying;

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
            Expanded(
              child: Text(
                verifying ? 'Checking the download' : 'Downloading model',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (!verifying) ...[
              Text('$pct%', style: Theme.of(context).textTheme.bodySmall),
              Semantics(
                identifier: 'model_cancel_${progress.modelId}',
                child: IconButton(
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
              ),
            ],
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 24, bottom: 8),
          child: Text(
            verifying
                ? 'Verifying the file is complete and undamaged…'
                : _detailLine(),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: verifying ? null : progress.fraction,
            minHeight: 6,
            backgroundColor: scheme.surfaceContainerHigh,
          ),
        ),
      ],
    );
  }

  String _detailLine() {
    final base = '${_mb(progress.receivedMb)} of ${_mb(progress.totalMb)}';
    final speed = progress.speedMbPerSec;
    final eta = progress.eta;
    if (speed == null) return base;
    final rate = '${speed.toStringAsFixed(1)} MB/s';
    if (eta == null) return '$base · $rate';
    return '$base · $rate · ${_duration(eta)} left';
  }

  String _duration(Duration d) {
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes >= 1) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }

  String _mb(double mb) {
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }
}

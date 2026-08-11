import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/backup_bundle.dart';
import '../../services/backup/backup_exception.dart';
import '../../services/backup/backup_scheduler.dart';
import '../../services/backup/backup_service.dart';
import '../../services/backup/restore_options.dart';
import '../../state/settings_controller.dart';

/// Encrypted export and, once a file is picked and its passphrase entered,
/// a preview-before-you-commit restore.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _passphraseController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _includeHistory = false;
  bool _includeCredentials = false;
  bool _exporting = false;

  Uint8List? _pickedBytes;
  String? _pickedFileName;
  final _importPassphraseController = TextEditingController();
  bool _previewing = false;
  bool _restoring = false;
  BackupBundle? _previewedBundle;
  BackupPreview? _preview;

  bool _restoreSettings = true;
  bool _restoreTones = true;
  bool _restoreAudiences = true;
  bool _restoreWorkflows = true;
  bool _restoreProviderConfigs = true;
  bool _restoreCredentials = false;
  HistoryRestoreStrategy _historyStrategy = HistoryRestoreStrategy.skip;

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
    _importPassphraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text('Export', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Saves your tones, audiences, workflows, cloud provider setup, '
              'and settings to one encrypted file. Anyone who gets the file '
              'still needs the passphrase below to open it.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passphraseController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Passphrase',
                helperText: 'You will need this again to restore the backup.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm passphrase',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _includeHistory,
              onChanged: (v) => setState(() => _includeHistory = v ?? false),
              title: const Text('Include rewrite history'),
              subtitle: const Text('Off by default — the most sensitive section.'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _includeCredentials,
              onChanged: (v) => setState(() => _includeCredentials = v ?? false),
              title: const Text('Include cloud provider keys'),
              subtitle: const Text(
                'Stores your API keys in the file, protected only by the '
                'passphrase above. Leave off unless you specifically need it.',
              ),
            ),
            if (_includeCredentials) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_outlined, color: scheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A weak passphrase is the only thing standing between '
                        'this file and your API keys.',
                        style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _exporting ? null : () => _export(context),
              icon: _exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_outlined),
              label: Text(_exporting ? 'Exporting…' : 'Export backup'),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const _ScheduledBackupsSection(),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            Text('Import', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Pick a backup file and preview what it contains before '
              'anything is applied.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(_pickedFileName ?? 'Choose backup file'),
            ),
            if (_pickedBytes != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _importPassphraseController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Passphrase',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _previewing ? null : () => _previewImport(context),
                icon: _previewing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_outlined),
                label: Text(_previewing ? 'Decrypting…' : 'Preview'),
              ),
            ],
            if (_preview != null) ...[
              const SizedBox(height: 16),
              _RestorePreviewCard(
                preview: _preview!,
                restoreSettings: _restoreSettings,
                onRestoreSettingsChanged: (v) => setState(() => _restoreSettings = v),
                restoreTones: _restoreTones,
                onRestoreTonesChanged: (v) => setState(() => _restoreTones = v),
                restoreAudiences: _restoreAudiences,
                onRestoreAudiencesChanged: (v) => setState(() => _restoreAudiences = v),
                restoreWorkflows: _restoreWorkflows,
                onRestoreWorkflowsChanged: (v) => setState(() => _restoreWorkflows = v),
                restoreProviderConfigs: _restoreProviderConfigs,
                onRestoreProviderConfigsChanged: (v) =>
                    setState(() => _restoreProviderConfigs = v),
                restoreCredentials: _restoreCredentials,
                onRestoreCredentialsChanged: (v) => setState(() => _restoreCredentials = v),
                historyStrategy: _historyStrategy,
                onHistoryStrategyChanged: (v) => setState(() => _historyStrategy = v),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _restoring ? null : () => _confirmRestore(context),
                icon: _restoring
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(_restoring ? 'Restoring…' : 'Restore'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final passphrase = _passphraseController.text;
    if (passphrase.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use a passphrase of at least 8 characters.')),
      );
      return;
    }
    if (passphrase != _confirmController.text) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Passphrases don\'t match.')));
      return;
    }

    setState(() => _exporting = true);
    try {
      final service = context.read<BackupService>();
      final bundle = await service.gather(
        includeHistory: _includeHistory,
        includeCredentials: _includeCredentials,
      );
      final fileBytes = await service.export(bundle, passphrase);

      final dir = await getTemporaryDirectory();
      final fileName = BackupService.suggestedFileName(bundle.createdAt);
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(fileBytes);

      if (!context.mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'Rescripto backup'),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (bytes == null) return;
    setState(() {
      _pickedBytes = bytes;
      _pickedFileName = file!.name;
      _preview = null;
      _previewedBundle = null;
    });
  }

  Future<void> _previewImport(BuildContext context) async {
    final bytes = _pickedBytes;
    if (bytes == null) return;

    setState(() => _previewing = true);
    try {
      final service = context.read<BackupService>();
      final bundle = await service.decrypt(bytes, _importPassphraseController.text);
      if (!mounted) return;
      setState(() {
        _previewedBundle = bundle;
        _preview = service.preview(bundle);
        _restoreCredentials = false;
      });
    } on BackupWrongPassphraseException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wrong passphrase, or the file is corrupted.')),
      );
    } on BackupNewerFormatException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This backup was made by a newer version of Rescripto. Update the app first.'),
        ),
      );
    } on BackupException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('This file isn\'t a valid backup.')));
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _confirmRestore(BuildContext context) async {
    final bundle = _previewedBundle;
    if (bundle == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text(
          _historyStrategy == HistoryRestoreStrategy.replace
              ? 'Your current rewrite history will be replaced. Everything '
                    'else restored merges with what\'s already on this device.'
              : 'Restored items merge with what\'s already on this device — '
                    'nothing already here is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    setState(() => _restoring = true);
    try {
      final service = context.read<BackupService>();
      await service.restore(
        bundle,
        RestoreOptions(
          applySettings: _restoreSettings,
          applyTones: _restoreTones,
          applyAudiences: _restoreAudiences,
          applyWorkflows: _restoreWorkflows,
          applyProviderConfigs: _restoreProviderConfigs,
          applyCredentials: _restoreCredentials,
          history: _historyStrategy,
        ),
      );
      if (!context.mounted) return;
      context.read<SettingsController>().refreshFromService();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Backup restored.')));
      setState(() {
        _pickedBytes = null;
        _pickedFileName = null;
        _previewedBundle = null;
        _preview = null;
        _importPassphraseController.clear();
      });
    } on BackupOlderSchemaException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This backup was made by a newer version of Rescripto. Update the app first.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }
}

class _RestorePreviewCard extends StatelessWidget {
  const _RestorePreviewCard({
    required this.preview,
    required this.restoreSettings,
    required this.onRestoreSettingsChanged,
    required this.restoreTones,
    required this.onRestoreTonesChanged,
    required this.restoreAudiences,
    required this.onRestoreAudiencesChanged,
    required this.restoreWorkflows,
    required this.onRestoreWorkflowsChanged,
    required this.restoreProviderConfigs,
    required this.onRestoreProviderConfigsChanged,
    required this.restoreCredentials,
    required this.onRestoreCredentialsChanged,
    required this.historyStrategy,
    required this.onHistoryStrategyChanged,
  });

  final BackupPreview preview;
  final bool restoreSettings;
  final ValueChanged<bool> onRestoreSettingsChanged;
  final bool restoreTones;
  final ValueChanged<bool> onRestoreTonesChanged;
  final bool restoreAudiences;
  final ValueChanged<bool> onRestoreAudiencesChanged;
  final bool restoreWorkflows;
  final ValueChanged<bool> onRestoreWorkflowsChanged;
  final bool restoreProviderConfigs;
  final ValueChanged<bool> onRestoreProviderConfigsChanged;
  final bool restoreCredentials;
  final ValueChanged<bool> onRestoreCredentialsChanged;
  final HistoryRestoreStrategy historyStrategy;
  final ValueChanged<HistoryRestoreStrategy> onHistoryStrategyChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Made ${preview.createdAt.toLocal()} · Rescripto ${preview.appVersion}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (preview.containsSecrets) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_outlined, color: scheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This file contains ${preview.credentialCount} cloud provider '
                        'key(s).',
                        style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (preview.hasSettings)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: restoreSettings,
                onChanged: (v) => onRestoreSettingsChanged(v ?? false),
                title: const Text('Settings'),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: restoreTones,
              onChanged: (v) => onRestoreTonesChanged(v ?? false),
              title: Text('Tones (${preview.toneCount})'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: restoreAudiences,
              onChanged: (v) => onRestoreAudiencesChanged(v ?? false),
              title: Text('Audiences (${preview.audienceCount})'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: restoreWorkflows,
              onChanged: (v) => onRestoreWorkflowsChanged(v ?? false),
              title: Text('Workflows (${preview.workflowCount})'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: restoreProviderConfigs,
              onChanged: (v) => onRestoreProviderConfigsChanged(v ?? false),
              title: Text('Cloud provider setup (${preview.providerConfigCount})'),
            ),
            if (preview.containsSecrets)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: restoreCredentials,
                onChanged: (v) => onRestoreCredentialsChanged(v ?? false),
                title: Text('Cloud provider keys (${preview.credentialCount})'),
              ),
            const SizedBox(height: 8),
            Text('Rewrite history (${preview.historyCount})', style: Theme.of(context).textTheme.bodyMedium),
            RadioGroup<HistoryRestoreStrategy>(
              groupValue: historyStrategy,
              onChanged: (v) => onHistoryStrategyChanged(v ?? HistoryRestoreStrategy.skip),
              child: const Column(
                children: [
                  RadioListTile<HistoryRestoreStrategy>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: HistoryRestoreStrategy.skip,
                    title: Text('Skip'),
                  ),
                  RadioListTile<HistoryRestoreStrategy>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: HistoryRestoreStrategy.append,
                    title: Text('Add to current history'),
                  ),
                  RadioListTile<HistoryRestoreStrategy>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: HistoryRestoreStrategy.replace,
                    title: Text('Replace current history'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Automatic, unattended local backups — see [BackupScheduler]'s own doc
/// for why this is an in-app timer rather than `workmanager`.
class _ScheduledBackupsSection extends StatefulWidget {
  const _ScheduledBackupsSection();

  @override
  State<_ScheduledBackupsSection> createState() => _ScheduledBackupsSectionState();
}

class _ScheduledBackupsSectionState extends State<_ScheduledBackupsSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final settingsController = context.watch<SettingsController>();
    final scheme = Theme.of(context).colorScheme;
    final lastBackup = settingsController.lastScheduledBackupAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Scheduled backups', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'About once a week when you open the app, writes an encrypted '
          'copy to this device\'s private storage and keeps the most '
          'recent ${BackupScheduler.retentionCount}. Nothing leaves the '
          'device — this isn\'t a substitute for the export above.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settingsController.scheduledBackupsEnabled,
          onChanged: _busy ? null : (v) => _toggle(context, v),
          title: const Text('Automatic local backups'),
          subtitle: Text(
            lastBackup == null ? 'No backup yet' : 'Last backup: ${lastBackup.toLocal()}',
          ),
        ),
        if (settingsController.scheduledBackupsEnabled) ...[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: settingsController.scheduledBackupIncludeHistory,
            onChanged: (v) => settingsController.setScheduledBackupIncludeHistory(v ?? false),
            title: const Text('Include rewrite history'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: settingsController.scheduledBackupIncludeCredentials,
            onChanged: (v) => settingsController.setScheduledBackupIncludeCredentials(v ?? false),
            title: const Text('Include cloud provider keys'),
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _changePassphrase(context),
            icon: const Icon(Icons.password_outlined),
            label: const Text('Change backup passphrase'),
          ),
        ],
      ],
    );
  }

  Future<void> _toggle(BuildContext context, bool enabled) async {
    final controller = context.read<SettingsController>();
    if (!enabled) {
      await controller.setScheduledBackupsEnabled(false);
      return;
    }

    final scheduler = context.read<BackupScheduler>();
    if (await scheduler.hasPassphrase()) {
      await controller.setScheduledBackupsEnabled(true);
      return;
    }

    if (!context.mounted) return;
    final passphrase = await _promptForPassphrase(context);
    if (passphrase == null || !context.mounted) return;
    await scheduler.setPassphrase(passphrase);
    await controller.setScheduledBackupsEnabled(true);
  }

  Future<void> _changePassphrase(BuildContext context) async {
    final passphrase = await _promptForPassphrase(context);
    if (passphrase == null || !context.mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<BackupScheduler>().setPassphrase(passphrase);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Backup passphrase updated.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _promptForPassphrase(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => _PassphraseDialog(),
    );
  }
}

class _PassphraseDialog extends StatefulWidget {
  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _passphraseController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Backup passphrase'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Used only for automatic backups, stored in this device\'s '
            'secure Keystore — never sent anywhere, never used for a '
            'manual export above.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passphraseController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Passphrase'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirm passphrase'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final passphrase = _passphraseController.text;
            if (passphrase.length < 8) {
              setState(() => _error = 'Use at least 8 characters.');
              return;
            }
            if (passphrase != _confirmController.text) {
              setState(() => _error = 'Passphrases don\'t match.');
              return;
            }
            Navigator.pop(context, passphrase);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

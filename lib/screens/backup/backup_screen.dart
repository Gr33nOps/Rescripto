import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/backup/backup_service.dart';

/// Encrypted export today; import lands alongside it once Step 2 exists.
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

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
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
}

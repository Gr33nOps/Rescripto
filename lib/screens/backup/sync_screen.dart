import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_messenger.dart';
import '../../services/backup/backup_exception.dart';
import '../../services/backup/backup_scheduler.dart';
import '../../services/backup/backup_service.dart';
import '../../services/backup/restore_options.dart';
import '../../services/credentials/credential_store.dart';
import '../../services/network/network_exceptions.dart';
import '../../services/sync/sync_service.dart';
import '../../services/sync/webdav_exception.dart';
import '../../services/sync/webdav_sync_conflict_exception.dart';
import '../../state/settings_controller.dart';

/// WebDAV/Nextcloud sync: server setup, per-section selection, and a
/// manual push/pull with a visible prompt whenever the server is ahead of
/// what this device last pushed — see [SyncService]'s own doc for why
/// nothing here ever applies a remote change automatically.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  late final _urlController = TextEditingController();
  late final _usernameController = TextEditingController();
  bool _busy = false;
  bool _testing = false;
  DateTime? _remoteNewerThan;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = context.read<SettingsController>();
      _urlController.text = settings.webdavUrl ?? '';
      _usernameController.text = settings.webdavUsername ?? '';
      _checkForRemoteChanges(context);
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsController = context.watch<SettingsController>();
    final scheme = Theme.of(context).colorScheme;
    final configured = (settingsController.webdavUrl ?? '').isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV sync')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
          children: [
            Text(
              'Sync one encrypted backup to a WebDAV server such as Nextcloud '
              'or ownCloud. Your server receives encrypted data, not readable '
              'text.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Semantics(
              identifier: 'sync_server_url_input',
              child: TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://cloud.example.com/remote.php/dav/files/me',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              identifier: 'sync_username_input',
              child: TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  identifier: 'sync_set_password_button',
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _setPassword(context),
                    icon: const Icon(Icons.password_outlined),
                    label: const Text('Set server password'),
                  ),
                ),
                const SizedBox(height: 8),
                Semantics(
                  identifier: 'sync_save_server_config_button',
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _saveServerConfig(context),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save'),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _testing ? null : () => _testConnection(context),
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering_outlined),
                  label: const Text('Test connection'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'What to sync',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Semantics(
              identifier: 'sync_toggle_settings',
              child: _SyncToggle(
                label: 'Settings',
                value: settingsController.syncIncludeSettings,
                onChanged: settingsController.setSyncIncludeSettings,
              ),
            ),
            Semantics(
              identifier: 'sync_toggle_presets',
              child: _SyncToggle(
                label: 'Tones & audiences',
                value: settingsController.syncIncludePresets,
                onChanged: settingsController.setSyncIncludePresets,
              ),
            ),
            Semantics(
              identifier: 'sync_toggle_workflows',
              child: _SyncToggle(
                label: 'Workflows',
                value: settingsController.syncIncludeWorkflows,
                onChanged: settingsController.setSyncIncludeWorkflows,
              ),
            ),
            Semantics(
              identifier: 'sync_toggle_provider_configs',
              child: _SyncToggle(
                label: 'Cloud provider setup',
                value: settingsController.syncIncludeProviderConfigs,
                onChanged: settingsController.setSyncIncludeProviderConfigs,
              ),
            ),
            Semantics(
              identifier: 'sync_toggle_history',
              child: _SyncToggle(
                label: 'Rewrite history',
                value: settingsController.syncIncludeHistory,
                onChanged: settingsController.setSyncIncludeHistory,
                subtitle:
                    'Off by default because history may contain private text.',
              ),
            ),
            Semantics(
              identifier: 'sync_toggle_credentials',
              child: _SyncToggle(
                label: 'Cloud provider keys',
                value: settingsController.syncIncludeCredentials,
                onChanged: settingsController.setSyncIncludeCredentials,
                subtitle: 'Sends your API keys to the server, encrypted.',
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            if (_remoteNewerThan != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.cloud_sync_outlined,
                      color: scheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'The server has a newer copy (${_remoteNewerThan!.toLocal()}).',
                            style: TextStyle(color: scheme.onTertiaryContainer),
                          ),
                          const SizedBox(height: 8),
                          Semantics(
                            identifier: 'sync_review_apply_button',
                            child: FilledButton(
                              onPressed: _busy ? null : () => _pull(context),
                              child: const Text('Review and apply'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Semantics(
              identifier: 'sync_button',
              child: FilledButton.icon(
                onPressed: (!configured || _busy) ? null : () => _push(context),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(_busy ? 'Working…' : 'Sync now'),
              ),
            ),
            if (settingsController.lastSyncPushAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last pushed: ${settingsController.lastSyncPushAt!.toLocal()}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _saveServerConfig(BuildContext context) async {
    final controller = context.read<SettingsController>();
    await controller.setWebdavUrl(_urlController.text.trim());
    await controller.setWebdavUsername(_usernameController.text.trim());
    if (!context.mounted) return;
    showAppSnackBar('Server settings saved.');
    _checkForRemoteChanges(context);
  }

  Future<void> _testConnection(BuildContext context) async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      showAppSnackBar('Enter a server URL first.');
      return;
    }
    setState(() => _testing = true);
    try {
      final sync = context.read<SyncService>();
      // Deliberately does not touch SettingsController — only the "Save"
      // button persists the URL/username the fields hold. This used to call
      // setWebdavUrl/setWebdavUsername before testing, so even a *failed*
      // test left the typed values saved.
      await sync.testConnection(url, _usernameController.text.trim());
      if (context.mounted) showAppSnackBar('Connected successfully.');
    } on WebDavException catch (error) {
      if (context.mounted) showAppSnackBar(_describe(error));
    } on NetworkBlockedByPolicyException {
      if (context.mounted) {
        showAppSnackBar('Backup sync is turned off in Privacy settings.');
      }
    } catch (_) {
      if (context.mounted) {
        showAppSnackBar(
          'Couldn’t connect. Check the server URL and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _setPassword(BuildContext context) async {
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _SinglePasswordDialog(
        title: 'Server password',
        helperText:
            'Stored in the secure Android Keystore and sent only to '
            'the WebDAV server above.',
      ),
    );
    if (password == null || !context.mounted) return;
    await context.read<CredentialStore>().write(
      SyncService.passwordRef,
      password,
    );
    if (!context.mounted) return;
    showAppSnackBar('Server password saved.');
  }

  Future<void> _checkForRemoteChanges(BuildContext context) async {
    final settings = context.read<SettingsController>();
    if ((settings.webdavUrl ?? '').isEmpty) return;
    try {
      final remote = await context
          .read<SyncService>()
          .remoteNewerThanLastPush();
      if (mounted) setState(() => _remoteNewerThan = remote);
    } catch (_) {
      // A failed background check just means no banner shows — "Sync now"
      // surfaces the real error if the user acts.
    }
  }

  Future<String?> _requirePassphrase(BuildContext context) async {
    final scheduler = context.read<BackupScheduler>();
    final alreadySet = await scheduler.hasPassphrase();
    if (!context.mounted) return null;
    if (alreadySet) {
      return context.read<CredentialStore>().read(
        BackupScheduler.passphraseRef,
      );
    }
    final passphrase = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _SinglePasswordDialog(
        title: 'Sync passphrase',
        helperText:
            'Encrypts the backup before it is sent. The same '
            'passphrase is used for scheduled local backups.',
        confirm: true,
      ),
    );
    if (passphrase == null) return null;
    await scheduler.setPassphrase(passphrase);
    return passphrase;
  }

  Future<void> _push(BuildContext context, {bool force = false}) async {
    // Busy from the first tap, not just once the network call starts: the
    // passphrase lookup ahead of it is itself an async gap with no other
    // visible feedback, which read as an ignored tap during QA.
    setState(() => _busy = true);
    try {
      final passphrase = await _requirePassphrase(context);
      if (passphrase == null || !context.mounted) return;

      final settings = context.read<SettingsController>();
      await context.read<SyncService>().push(
        passphrase,
        includeSettings: settings.syncIncludeSettings,
        includeTones: settings.syncIncludePresets,
        includeAudiences: settings.syncIncludePresets,
        includeWorkflows: settings.syncIncludeWorkflows,
        includeProviderConfigs: settings.syncIncludeProviderConfigs,
        includeHistory: settings.syncIncludeHistory,
        includeCredentials: settings.syncIncludeCredentials,
        force: force,
      );
      if (!context.mounted) return;
      settings.refreshFromService();
      setState(() => _remoteNewerThan = null);
      showAppSnackBar('Synced.');
    } on WebDavSyncConflictException catch (e) {
      if (!context.mounted) return;
      setState(() => _busy = false);
      await _resolveConflict(context, e);
      return;
    } on WebDavException catch (e) {
      if (!context.mounted) return;
      showAppSnackBar(_describe(e));
    } on NetworkBlockedByPolicyException {
      if (!context.mounted) return;
      showAppSnackBar('Backup sync is turned off in Privacy settings.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Someone else's push (or this device's own stale view of the server)
  /// means proceeding would silently overwrite data this device has never
  /// seen — see [SyncService.push]'s doc. Lets the user pull that copy
  /// first instead of guessing, or explicitly accept overwriting it.
  Future<void> _resolveConflict(
    BuildContext context,
    WebDavSyncConflictException error,
  ) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('The server copy has changed'),
        content: Text(
          'Another device has synced since this one last checked'
          '${error.remoteModifiedAt != null ? ' (${error.remoteModifiedAt!.toLocal()})' : ''}. '
          'Pushing now would overwrite it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'pull'),
            child: const Text('Review server copy'),
          ),
          Semantics(
            identifier: 'sync_conflict_overwrite_button',
            child: FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'overwrite'),
              child: const Text('Overwrite anyway'),
            ),
          ),
        ],
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'pull') {
      await _pull(context);
    } else if (choice == 'overwrite') {
      await _push(context, force: true);
    }
  }

  Future<void> _pull(BuildContext context) async {
    // See _push's comment: busy from the first tap, before the passphrase
    // lookup's own async gap.
    setState(() => _busy = true);
    try {
      final passphrase = await _requirePassphrase(context);
      if (passphrase == null || !context.mounted) return;

      final service = context.read<BackupService>();
      final bundle = await context.read<SyncService>().pull(passphrase);
      if (!context.mounted) return;
      final preview = service.preview(bundle);

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Apply the server\'s copy?'),
          content: Text(
            'Made ${preview.createdAt.toLocal()}. Restored items are added to '
            'what is already on this device. Nothing currently here will be '
            'deleted.${preview.containsSecrets ? '\n\nThis copy includes cloud provider keys.' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            Semantics(
              identifier: 'sync_apply_confirm',
              child: FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;

      await service.restore(
        bundle,
        RestoreOptions(applyCredentials: preview.containsSecrets),
      );
      if (!context.mounted) return;
      context.read<SettingsController>().refreshFromService();
      setState(() => _remoteNewerThan = null);
      showAppSnackBar('Applied the server\'s copy.');
    } on WebDavException catch (e) {
      if (!context.mounted) return;
      showAppSnackBar(_describe(e));
    } on BackupException {
      if (!context.mounted) return;
      showAppSnackBar('Wrong passphrase, or the remote file is corrupted.');
    } on NetworkBlockedByPolicyException {
      if (!context.mounted) return;
      showAppSnackBar('Backup sync is turned off in Privacy settings.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describe(WebDavException e) {
    if (e.isAuthFailure) return 'Server rejected the username/password.';
    if (e.isNotFound) return 'Nothing has been synced to this server yet.';
    // A null statusCode with a message is a local validation failure (e.g.
    // an invalid server URL) rather than a real HTTP response — the message
    // is the useful part, not a status code that doesn't exist.
    if (e.statusCode == null && e.message != null) return e.message!;
    return 'Sync failed (${e.statusCode ?? 'connection error'}).';
  }
}

class _SyncToggle extends StatelessWidget {
  const _SyncToggle({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle!),
    );
  }
}

class _SinglePasswordDialog extends StatefulWidget {
  const _SinglePasswordDialog({
    required this.title,
    required this.helperText,
    this.confirm = false,
  });

  final String title;
  final String helperText;
  final bool confirm;

  @override
  State<_SinglePasswordDialog> createState() => _SinglePasswordDialogState();
}

class _SinglePasswordDialogState extends State<_SinglePasswordDialog> {
  final _controller = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.helperText, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          Semantics(
            identifier: 'sync_password_dialog_input',
            child: TextField(
              controller: _controller,
              obscureText: true,
              onChanged: (_) => _clearError(),
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ),
          if (widget.confirm) ...[
            const SizedBox(height: 12),
            Semantics(
              identifier: 'sync_password_dialog_confirm',
              child: TextField(
                controller: _confirmController,
                obscureText: true,
                onChanged: (_) => _clearError(),
                decoration: const InputDecoration(labelText: 'Confirm'),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        Semantics(
          identifier: 'sync_password_dialog_save',
          child: FilledButton(
            onPressed: () {
              final value = _controller.text;
              if (value.length < 8) {
                setState(() => _error = 'Use at least 8 characters.');
                return;
              }
              if (widget.confirm && value != _confirmController.text) {
                setState(() => _error = 'Doesn\'t match.');
                return;
              }
              Navigator.pop(context, value);
            },
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }
}

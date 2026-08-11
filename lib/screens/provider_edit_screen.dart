import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/engine_error_messages.dart';
import '../engine/engine_exception.dart';
import '../models/provider_config.dart';
import '../models/provider_preset.dart';
import '../services/credentials/credential_ref.dart';
import '../services/credentials/credential_store.dart';
import '../services/network/network_guard.dart';
import '../services/providers/provider_connection_tester.dart';
import '../services/providers/provider_registry.dart';

/// Add or edit one configured provider.
///
/// The key field is `obscureText` and never repopulated on reopen —
/// [CredentialStore] has no read-for-display path and must not grow one.
/// Once a provider is saved, its key is shown only as "•••• configured";
/// typing a new value and saving replaces it, and "Remove key" deletes it
/// outright. "Test connection" tests whatever key is currently saved, so a
/// freshly-typed key needs a save first — keeping the test path simple and
/// exactly matching what a rewrite would actually use.
class ProviderEditScreen extends StatefulWidget {
  const ProviderEditScreen({super.key, this.presetId, this.existing})
    : assert(
        presetId != null || existing != null,
        'Provide either presetId (new) or existing (edit).',
      );

  /// Set when creating a new config over this preset.
  final String? presetId;

  /// Set when editing an already-saved config.
  final ProviderConfig? existing;

  @override
  State<ProviderEditScreen> createState() => _ProviderEditScreenState();
}

class _ProviderEditScreenState extends State<ProviderEditScreen> {
  late final ProviderConfig? _existing = widget.existing;
  late final ProviderPreset _preset =
      widget.existing?.preset ?? ProviderPresetCatalog.byId(widget.presetId!)!;
  late final _nameController = TextEditingController(
    text: widget.existing?.displayName ?? _preset.displayName,
  );
  late final _baseUrlController = TextEditingController(
    text: widget.existing?.baseUrlOverride ?? (_preset.editableBaseUrl ? _preset.baseUrl : ''),
  );
  final _keyController = TextEditingController();

  bool _hasStoredKey = false;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;
  bool _testFailed = false;

  @override
  void initState() {
    super.initState();
    _refreshStoredKeyState();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _refreshStoredKeyState() async {
    final existing = _existing;
    if (existing == null) return;
    final has = await context.read<CredentialStore>().has(existing.credential);
    if (mounted) setState(() => _hasStoredKey = has);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _existing == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Add ${_preset.displayName}' : 'Edit ${_existing.displayName}'),
        actions: [
          if (!isNew)
            IconButton(
              tooltip: 'Delete provider',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Display name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (_preset.editableBaseUrl)
              TextField(
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'http://localhost:11434/v1',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              )
            else
              _ReadOnlyField(label: 'Base URL', value: _preset.baseUrl),
            const SizedBox(height: 16),
            TextField(
              controller: _keyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _preset.requiresKey ? 'API key' : 'API key (optional)',
                hintText: _hasStoredKey ? '•••• configured · type to replace' : 'Paste your API key',
                border: const OutlineInputBorder(),
                suffixIcon: _hasStoredKey
                    ? IconButton(
                        tooltip: 'Remove saved key',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _removeKey,
                      )
                    : null,
              ),
            ),
            if (_preset.docsUrl != null) ...[
              const SizedBox(height: 4),
              Text(
                'Get a key from ${_preset.docsUrl}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(isNew ? 'Add provider' : 'Save'),
            ),
            const SizedBox(height: 12),
            if (!isNew) ...[
              OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering_outlined),
                label: const Text('Test connection'),
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 8),
                Text(
                  _testResult!,
                  style: TextStyle(
                    color: _testFailed
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ] else
              Text(
                'Save this provider first, then reopen it to test the connection.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final registry = context.read<ProviderRegistry>();
      final credentialStore = context.read<CredentialStore>();
      final existing = _existing;
      final id = existing?.id ?? registry.newConfigId(_preset.id);
      final credential =
          existing?.credential ?? CredentialRef(providerId: id, kind: CredentialKind.apiKey);
      final now = DateTime.now();

      final name = _nameController.text.trim();
      final baseUrlOverride = _preset.editableBaseUrl ? _baseUrlController.text.trim() : null;
      if (_preset.editableBaseUrl && (baseUrlOverride == null || baseUrlOverride.isEmpty)) {
        throw ArgumentError('Base URL is required for this provider.');
      }

      final config = ProviderConfig(
        id: id,
        presetId: _preset.id,
        displayName: name.isEmpty ? _preset.displayName : name,
        credential: credential,
        baseUrlOverride: baseUrlOverride,
        enabled: existing?.enabled ?? true,
        models: existing?.models ?? const [],
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
      config.baseUrl; // validates scheme/shape early, throws ArgumentError

      await registry.save(config);

      final typedKey = _keyController.text.trim();
      if (typedKey.isNotEmpty) {
        await credentialStore.write(credential, typedKey);
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Couldn’t save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeKey() async {
    final existing = _existing;
    if (existing == null) return;
    await context.read<CredentialStore>().delete(existing.credential);
    _keyController.clear();
    if (mounted) setState(() => _hasStoredKey = false);
  }

  Future<void> _testConnection() async {
    final existing = _existing;
    if (existing == null) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final tester = ProviderConnectionTester(
        context.read<NetworkGuard>(),
        context.read<CredentialStore>(),
      );
      await tester.test(existing);
      if (!mounted) return;
      setState(() {
        _testResult = 'Connected successfully.';
        _testFailed = false;
      });
    } on EngineException catch (e) {
      if (!mounted) return;
      setState(() {
        _testResult = describeEngineError(e);
        _testFailed = true;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _confirmDelete() async {
    final existing = _existing;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${existing.displayName}?'),
        content: const Text('This removes the provider and its saved API key from this device.'),
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
    if (confirmed != true || !mounted) return;
    await context.read<ProviderRegistry>().delete(existing.id);
    if (mounted) Navigator.of(context).pop();
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: TextEditingController(text: value),
      readOnly: true,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }
}

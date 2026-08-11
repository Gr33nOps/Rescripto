import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/provider_config.dart';
import '../models/provider_preset.dart';
import '../services/credentials/credential_store.dart';
import '../services/providers/provider_registry.dart';
import 'provider_edit_screen.dart';

/// Configured cloud providers: which are set up, whether each has a key,
/// and enable/disable/delete.
///
/// Shows "Key configured" or "No key" from [CredentialStore.listRefs] /
/// [CredentialStore.has] — ids only, which is literally what the
/// `credential_ref` migration's own doc says that table is for.
/// [CredentialStore] has no read-for-display path and must not grow one.
class ProvidersScreen extends StatelessWidget {
  const ProvidersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final registry = context.watch<ProviderRegistry>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Cloud providers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pickPreset(context),
        icon: const Icon(Icons.add),
        label: const Text('Add provider'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'A configured provider only receives text when you '
                      'pick it in Cloud or Hybrid mode, and only if Cloud '
                      'rewriting is on in Privacy settings.',
                      style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (registry.configs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'No providers configured yet.\nTap "Add provider" to get started.',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              for (final config in registry.configs) ...[
                _ProviderTile(config: config),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickPreset(BuildContext context) async {
    final preset = await showModalBottomSheet<ProviderPreset>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        children: [
          for (final preset in ProviderPresetCatalog.all)
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: Text(preset.displayName),
              subtitle: Text(preset.editableBaseUrl ? 'Custom base URL' : preset.baseUrl),
              onTap: () => Navigator.pop(sheetContext, preset),
            ),
        ],
      ),
    );
    if (preset == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProviderEditScreen(presetId: preset.id)),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({required this.config});

  final ProviderConfig config;

  @override
  Widget build(BuildContext context) {
    final registry = context.read<ProviderRegistry>();
    final credentialStore = context.read<CredentialStore>();

    return Card(
      child: ListTile(
        leading: const Icon(Icons.cloud_outlined),
        title: Text(config.displayName),
        subtitle: FutureBuilder<bool>(
          future: credentialStore.has(config.credential),
          builder: (context, snapshot) {
            final hasKey = snapshot.data;
            final keyLabel = hasKey == null
                ? 'Checking key…'
                : hasKey
                ? '•••• configured'
                : config.preset.requiresKey
                ? 'No key'
                : 'No key needed';
            return Text('${config.preset.displayName} · $keyLabel');
          },
        ),
        trailing: Switch(
          value: config.enabled,
          onChanged: (v) => registry.setEnabled(config.id, v),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProviderEditScreen(existing: config)),
        ),
      ),
    );
  }
}

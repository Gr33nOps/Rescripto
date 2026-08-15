import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/provider_config.dart';
import '../models/provider_preset.dart';
import '../services/credentials/credential_store.dart';
import '../services/providers/provider_registry.dart';
import '../services/routing/target_router.dart';
import '../state/settings_controller.dart';
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
      floatingActionButton: Semantics(
        identifier: 'provider_add_button',
        child: FloatingActionButton.extended(
          onPressed: () => _pickPreset(context),
          icon: const Icon(Icons.add),
          label: const Text('Add provider'),
        ),
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
                      style: TextStyle(
                        color: scheme.onSecondaryContainer,
                        fontSize: 13,
                      ),
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else ...[
              const _ActiveCloudModelCard(),
              const SizedBox(height: 16),
              for (final config in registry.configs) ...[
                _ProviderTile(config: config),
                const SizedBox(height: 8),
              ],
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
            Semantics(
              identifier: 'provider_preset_${preset.id}',
              child: ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: Text(preset.displayName),
                subtitle: Text(
                  preset.editableBaseUrl ? 'Custom base URL' : preset.baseUrl,
                ),
                onTap: () => Navigator.pop(sheetContext, preset),
              ),
            ),
        ],
      ),
    );
    if (preset == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProviderEditScreen(presetId: preset.id),
      ),
    );
  }
}

/// Which provider and model a cloud rewrite will actually use.
///
/// Reads the answer from [TargetRouter] rather than re-deriving it, so this
/// can never disagree with what routing does — the failure that made cloud
/// unusable before was exactly a disagreement of that kind, with a provider
/// visibly configured and passing its connection test while routing reported
/// "no cloud provider configured".
class _ActiveCloudModelCard extends StatelessWidget {
  const _ActiveCloudModelCard();

  @override
  Widget build(BuildContext context) {
    // Watched, not read: changing the selection writes through
    // SettingsController, and this card has to repaint when it does.
    context.watch<SettingsController>();
    final registry = context.watch<ProviderRegistry>();
    final router = context.read<TargetRouter>();
    final scheme = Theme.of(context).colorScheme;

    final provider = router.effectiveCloudProvider;
    final modelRef = provider == null
        ? null
        : router.effectiveCloudModelRef(provider);

    final subtitle = switch ((provider, modelRef)) {
      (null, _) when registry.enabledConfigs.isEmpty =>
        'No provider is enabled. Choose one below to use cloud rewriting.',
      (null, _) => 'No provider selected.',
      (final p?, null) =>
        'No model available for ${p.displayName}. Add one when editing it.',
      (final p?, final m?) => '${p.displayName} · $m',
    };

    return Card(
      child: Semantics(
        identifier: 'provider_active_model_card',
        child: ListTile(
          leading: Icon(Icons.auto_awesome_outlined, color: scheme.primary),
          title: const Text('Used for cloud rewriting'),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: registry.enabledConfigs.isEmpty ? null : () => _pick(context),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final registry = context.read<ProviderRegistry>();
    final settings = context.read<SettingsController>();

    final choice =
        await showModalBottomSheet<(String providerId, String modelRef)>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (sheetContext) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollController) => ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Text(
                  'Choose a model',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                for (final config in registry.enabledConfigs) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      config.displayName,
                      style: Theme.of(sheetContext).textTheme.labelLarge,
                    ),
                  ),
                  if (config.allModels.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'No models listed. Add one when editing this provider.',
                        style: Theme.of(sheetContext).textTheme.bodySmall,
                      ),
                    )
                  else
                    for (final model in config.allModels)
                      Semantics(
                        identifier: 'provider_model_option_${model.modelRef}',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.memory_outlined),
                          title: Text(model.displayName),
                          onTap: () => Navigator.pop(sheetContext, (
                            config.id,
                            model.modelRef,
                          )),
                        ),
                      ),
                ],
              ],
            ),
          ),
        );

    if (choice == null) return;
    // Both halves, always together: a provider id without a matching model
    // ref is the stale-pairing case `TargetRouter._modelRefFor` has to guard
    // against, and there is no reason to create one here.
    await settings.setCloudProviderId(choice.$1);
    await settings.setCloudModelRef(choice.$2);
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
      child: Semantics(
        identifier: 'provider_tile_${config.id}',
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
          trailing: Semantics(
            identifier: 'provider_enable_switch_${config.id}',
            child: Switch(
              value: config.enabled,
              onChanged: (v) => registry.setEnabled(config.id, v),
            ),
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProviderEditScreen(existing: config),
            ),
          ),
        ),
      ),
    );
  }
}

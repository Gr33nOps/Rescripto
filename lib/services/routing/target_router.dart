import '../../engine/engine_target.dart';
import '../../models/processing_mode.dart';
import '../../models/provider_config.dart';
import '../network/network_feature.dart';
import '../network/network_policy.dart';
import '../providers/provider_registry.dart';
import '../settings_service.dart';

/// Why [RoutingDecision.target] is null — nothing was actually runnable.
enum RoutingBlocker {
  /// The selected local model isn't installed.
  noLocalModel,

  /// Cloud mode/Hybrid needs a provider, and none is configured and enabled.
  noCloudProvider,

  /// A provider is configured, but `cloudRewrite` is off or the kill switch
  /// is on — distinct from [noCloudProvider] so the UI can point at Privacy
  /// settings instead of the provider list.
  cloudDisabledByPolicy,
}

/// Where a rewrite should run, and why — read during widget `build()`, so
/// nothing here does I/O or throws.
class RoutingDecision {
  const RoutingDecision({required this.target, required this.reason, this.fallback, this.blocker});

  /// Null only when [blocker] explains why nothing is available at all.
  final EngineTarget? target;

  /// One sentence, shown verbatim by the processing indicator. A hybrid
  /// decision that doesn't say which way it leans, and why, is the failure
  /// mode this field exists to avoid.
  final String reason;

  /// The other engine, if [target] fails — only set in Hybrid mode when a
  /// genuine alternative exists. `RewriteController` decides whether using
  /// it needs the user's permission first (local→cloud does; cloud→local
  /// doesn't — see its own doc).
  final EngineTarget? fallback;

  final RoutingBlocker? blocker;

  bool get isBlocked => target == null;
}

/// Decides which engine a rewrite should run on: Local, Cloud, or —
/// in Hybrid — whichever of the two is actually usable.
///
/// Replaces the hardcoded `'local.llama'` target `RewriteController._target`
/// used to build directly; that field's own comment already named this file
/// as where the real logic belongs once a second engine existed.
///
/// **Cloud "availability" here checks the provider is configured and
/// enabled and that policy allows it — not that a credential is actually
/// present in the Keystore.** That check is inherently async (a Keystore
/// read), and this has to run synchronously inside `build()`. If the
/// credential turns out to be missing anyway (wiped by the panic button,
/// say, without the picker having refreshed), `CloudRewriteEngine` still
/// catches it and throws `ProviderNotConfiguredException` — routing is a
/// best-effort forecast, not the last line of defence.
class TargetRouter {
  const TargetRouter({
    required this.settings,
    required this.providerRegistry,
    required this.networkPolicy,
    required this.isLocalModelInstalled,
  });

  final SettingsService settings;
  final ProviderRegistry providerRegistry;
  final NetworkPolicy networkPolicy;

  /// Whether the currently-selected local GGUF model is installed. A
  /// callback rather than a direct `ModelsController` dependency, so this
  /// stays decoupled from the models screen's own state.
  final bool Function() isLocalModelInstalled;

  /// Above this many characters, Hybrid prefers cloud — long input is where
  /// a small on-device model's context window and speed both suffer most.
  static const hybridLengthThreshold = 1500;

  RoutingDecision route({required int inputLength}) => switch (settings.processingMode) {
    ProcessingMode.local => _localOnly(),
    ProcessingMode.cloud => _cloudOnly(),
    ProcessingMode.hybrid => _hybrid(inputLength),
  };

  EngineTarget get _localTarget =>
      EngineTarget(engineId: 'local.llama', modelRef: settings.selectedModelId);

  bool get _cloudPolicyAllows =>
      !networkPolicy.killSwitch && networkPolicy.isAllowed(NetworkFeature.cloudRewrite);

  /// The provider a cloud rewrite would use.
  ///
  /// Falls back to the first enabled provider when `cloudProviderId` names
  /// nothing usable. Without that fallback this returned null whenever the
  /// setting was unset — and nothing in the app ever set it, so a user could
  /// add a provider, save a key, pass "Test connection", and still be told
  /// "no cloud provider configured" forever. Deriving the answer from what
  /// is actually configured means the state the user can see (a provider,
  /// enabled, with a key) is the state that decides routing.
  ProviderConfig? get _selectedProvider {
    final id = settings.cloudProviderId;
    if (id != null) {
      final config = providerRegistry.byId(id);
      if (config != null && config.enabled) return config;
    }
    final enabled = providerRegistry.enabledConfigs;
    return enabled.isEmpty ? null : enabled.first;
  }

  /// The model a cloud rewrite would use on [provider].
  ///
  /// Same reasoning as [_selectedProvider]: prefer the explicit choice, but
  /// fall back to the provider's own first known model rather than refusing
  /// to route. Every preset ships a `knownModels` list, so this is null only
  /// for a custom endpoint whose model list the user hasn't filled in — the
  /// one case where there genuinely is nothing to pick.
  String? _modelRefFor(ProviderConfig provider) {
    final models = provider.allModels;
    final explicit = settings.cloudModelRef;

    // Honoured only when this provider actually offers it. A ref left over
    // from a different provider — after switching providers, or restoring a
    // backup — would otherwise be sent to an API that has never heard of it,
    // failing as a confusing 404 rather than falling back to something that
    // works. Every model the picker can select comes from `allModels`, so a
    // legitimate choice always passes this check, including a custom model
    // the user added to this provider themselves.
    if (explicit != null &&
        explicit.isNotEmpty &&
        models.any((m) => m.modelRef == explicit)) {
      return explicit;
    }

    return models.isEmpty ? null : models.first.modelRef;
  }

  EngineTarget? get _cloudTarget {
    if (!_cloudPolicyAllows) return null;
    final provider = _selectedProvider;
    if (provider == null) return null;
    final modelRef = _modelRefFor(provider);
    if (modelRef == null) return null;
    return provider.targetFor(modelRef);
  }

  /// Which provider a cloud rewrite would actually use right now, whether
  /// that came from an explicit choice or the fallback. Exposed so the
  /// provider screen can show the real answer rather than re-deriving it and
  /// risking a UI that disagrees with what routing does.
  ProviderConfig? get effectiveCloudProvider => _selectedProvider;

  /// Which model [provider] would be asked for, same reasoning as
  /// [effectiveCloudProvider].
  String? effectiveCloudModelRef(ProviderConfig provider) => _modelRefFor(provider);

  RoutingDecision _localOnly() {
    if (!isLocalModelInstalled()) {
      return const RoutingDecision(
        target: null,
        reason: 'Local — no model installed',
        blocker: RoutingBlocker.noLocalModel,
      );
    }
    return RoutingDecision(target: _localTarget, reason: 'Local — on this device');
  }

  RoutingDecision _cloudOnly() {
    final target = _cloudTarget;
    if (target == null) {
      return RoutingDecision(
        target: null,
        reason: _cloudPolicyAllows ? 'Cloud — no provider configured' : 'Cloud — disabled in Privacy settings',
        blocker: _cloudPolicyAllows
            ? RoutingBlocker.noCloudProvider
            : RoutingBlocker.cloudDisabledByPolicy,
      );
    }
    return RoutingDecision(target: target, reason: 'Cloud — ${_selectedProvider!.displayName}');
  }

  RoutingDecision _hybrid(int inputLength) {
    final localOk = isLocalModelInstalled();
    final cloudTarget = _cloudTarget;
    final cloudOk = cloudTarget != null;
    final preferCloud = inputLength > hybridLengthThreshold;

    if (preferCloud && cloudOk) {
      return RoutingDecision(
        target: cloudTarget,
        reason: 'Hybrid — cloud (${_selectedProvider!.displayName}), long input',
        fallback: localOk ? _localTarget : null,
      );
    }
    if (localOk) {
      return RoutingDecision(
        target: _localTarget,
        reason: preferCloud
            ? 'Hybrid — local (no cloud provider set up for this long input)'
            : 'Hybrid — local, short input',
        fallback: cloudOk ? cloudTarget : null,
      );
    }
    if (cloudOk) {
      return RoutingDecision(
        target: cloudTarget,
        reason: 'Hybrid — cloud (${_selectedProvider!.displayName}), no local model installed',
      );
    }
    return const RoutingDecision(
      target: null,
      reason: 'Hybrid — nothing available yet',
      blocker: RoutingBlocker.noLocalModel,
    );
  }
}

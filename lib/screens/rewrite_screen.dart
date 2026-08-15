import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_messenger.dart';
import '../core/app_routes.dart';
import '../core/app_tab.dart';
import '../engine/engine_capabilities.dart';
import '../engine/engine_error_messages.dart';
import '../engine/engine_exception.dart';
import '../engine/engine_stage.dart';
import '../engine/engine_target.dart';
import '../models/ui_mode.dart';
import '../services/config_store.dart';
import '../services/network/network_policy.dart';
import '../services/providers/provider_registry.dart';
import '../services/routing/target_router.dart';
import '../services/share_intent_bridge.dart';
import '../state/models_controller.dart';
import '../state/rewrite_controller.dart';
import '../state/settings_controller.dart';
import '../widgets/mic_button.dart';
import '../widgets/processing_indicator.dart';
import '../widgets/result_view.dart';
import '../widgets/rewrite_controls.dart';
import '../widgets/tab_navigator.dart';
import '../widgets/tone_selector.dart';

/// The core "type, pick a tone, rewrite" screen.
class RewriteScreen extends StatefulWidget {
  const RewriteScreen({super.key});

  @override
  State<RewriteScreen> createState() => _RewriteScreenState();
}

class _RewriteScreenState extends State<RewriteScreen> {
  /// Which variant `ResultView` is currently showing. Mirrored here because
  /// "Insert & return" has to send the variant the user is actually looking
  /// at — it used to send `lastResult.primary.text`, which is always V1.
  int _selectedVariant = 0;

  /// The text "Insert & return" should hand back, clamped because a new
  /// result can arrive with fewer variants than the last selection.
  String _selectedText(RewriteController controller) {
    final outputs = controller.lastResult?.outputs ?? const [];
    if (outputs.isEmpty) return '';
    return outputs[_selectedVariant.clamp(0, outputs.length - 1)].text;
  }

  @override
  Widget build(BuildContext context) {
    // `RewriteController.routing` depends on `NetworkPolicy` (kill switch,
    // per-feature toggles) as well as the controller's own state — watching
    // it here too keeps `_TargetNotReadyBanner` live when a Privacy setting
    // changes on another screen, instead of showing a stale blocked/ready
    // state until something unrelated triggers a rebuild. See
    // `ProcessingIndicator`'s own doc for the same reasoning.
    context.watch<NetworkPolicy>();
    final controller = context.watch<RewriteController>();
    final models = context.watch<ModelsController>();
    final settings = context.watch<SettingsController>();
    final shareIntent = context.watch<ShareIntentBridge>();
    final isPro = settings.uiMode == UiMode.pro;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image(
              image: const AssetImage('assets/icon/app_icon_foreground.png'),
              height: 26,
              width: 26,
              color: Theme.of(context).colorScheme.onSurface,
              colorBlendMode: BlendMode.srcIn,
              semanticLabel: 'Rescripto logo',
            ),
            const SizedBox(width: 10),
            const Text('Rescripto'),
          ],
        ),
        actions: [
          Semantics(
            identifier: 'ui_mode_toggle',
            child: IconButton(
              tooltip: isPro ? 'Switch to Simple mode' : 'Switch to Pro mode',
              onPressed: () => _toggleUiMode(context, isPro: isPro),
              icon: Icon(isPro ? Icons.tune : Icons.tune_outlined),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: ProcessingIndicator(),
          ),
          if (controller.isRunning)
            Semantics(
              identifier: 'cancel_generation',
              child: IconButton(
                tooltip: 'Stop',
                onPressed: controller.isCancelling ? null : controller.stop,
                icon: const Icon(Icons.stop_circle_outlined),
              ),
            ),
        ],
      ),
      bottomNavigationBar: isPro
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _RewriteButton(
                running: controller.isRunning,
                cancelling: controller.isCancelling,
                onRewrite: () => _rewrite(controller),
                onStop: controller.stop,
              ),
            )
          : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
          children: [
            if (controller.routing.isBlocked && !models.scanning)
              _TargetNotReadyBanner(blocker: controller.routing.blocker!),
            if (shareIntent.awaitingProcessTextResult) ...[
              const SizedBox(height: 12),
              const _ProcessTextBanner(),
            ],
            const SizedBox(height: 12),
            const _SourceInput(),
            const SizedBox(height: 12),
            MicButton(onResult: (t) => _applyTranscript(controller, t)),
            const SizedBox(height: 20),
            Text('Tone', style: _sectionStyle(context)),
            const SizedBox(height: 8),
            ToneSelector(
              selectedId: controller.toneId,
              onChanged: controller.setTone,
            ),
            if (isPro) ...[
              const SizedBox(height: 20),
              RewriteControls(
                intensity: controller.intensity,
                length: controller.length,
                onIntensityChanged: controller.setIntensity,
                onLengthChanged: controller.setLength,
              ),
              const SizedBox(height: 20),
              Text('Audience', style: _sectionStyle(context)),
              const SizedBox(height: 8),
              _AudienceSelector(
                selected: controller.audience,
                onToggle: controller.toggleAudience,
              ),
              const SizedBox(height: 20),
              Text(
                'Extra instructions (optional)',
                style: _sectionStyle(context),
              ),
              const SizedBox(height: 8),
              _InstructionInput(
                value: controller.customInstruction,
                onChanged: controller.setCustomInstruction,
              ),
              const SizedBox(height: 20),
              Text('Variants', style: _sectionStyle(context)),
              const SizedBox(height: 8),
              Semantics(
                identifier: 'variant_count_selector',
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1')),
                    ButtonSegment(value: 2, label: Text('2')),
                    ButtonSegment(value: 3, label: Text('3')),
                  ],
                  selected: {controller.variantCount},
                  onSelectionChanged: (s) => controller.setVariantCount(s.first),
                  showSelectedIcon: false,
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (!isPro)
              _RewriteButton(
                running: controller.isRunning,
                cancelling: controller.isCancelling,
                onRewrite: () => _rewrite(controller),
                onStop: controller.stop,
              ),
            const SizedBox(height: 16),
            if (controller.isRunning)
              _StreamingPanel(
                text: controller.streamingText,
                stage: controller.stage,
                capabilities: controller.capabilities,
                cancelling: controller.isCancelling,
              ),
            if (controller.lastResult != null) ...[
              const SizedBox(height: 8),
              ResultView(
                result: controller.lastResult!,
                onVariantSelected: (index) {
                  if (index != _selectedVariant) {
                    setState(() => _selectedVariant = index);
                  }
                },
              ),
              const SizedBox(height: 8),
              Semantics(
                identifier: 'rewrite_again_button',
                child: OutlinedButton.icon(
                  onPressed: () => _rewrite(controller),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Rewrite again'),
                ),
              ),
              if (shareIntent.awaitingProcessTextResult) ...[
                const SizedBox(height: 8),
                Semantics(
                  identifier: 'insert_result',
                  child: FilledButton.icon(
                    onPressed: () =>
                        shareIntent.finishProcessText(_selectedText(controller)),
                    icon: const Icon(Icons.keyboard_return_outlined),
                    label: const Text('Insert & return'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  TextStyle _sectionStyle(BuildContext context) {
    return Theme.of(context).textTheme.labelLarge!.copyWith(
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }

  void _applyTranscript(RewriteController controller, String transcript) {
    final current = controller.sourceText.trim();
    controller.setSource(
      current.isEmpty ? transcript : '$current\n$transcript',
    );
  }

  /// Flips the persisted mode and pins/restores `RewriteController`'s
  /// editor state to match — the two halves of a Simple↔Pro transition
  /// `SettingsController.setUiMode` deliberately leaves separate. See
  /// `RewriteController.enterSimpleMode`'s own doc for why hiding alone
  /// isn't enough.
  void _toggleUiMode(BuildContext context, {required bool isPro}) {
    final rewrite = context.read<RewriteController>();
    if (isPro) {
      rewrite.enterSimpleMode();
      context.read<SettingsController>().setUiMode(UiMode.simple);
    } else {
      rewrite.enterProMode();
      context.read<SettingsController>().setUiMode(UiMode.pro);
    }
  }

  Future<void> _rewrite(RewriteController controller) async {
    FocusScope.of(context).unfocus();
    try {
      await controller.rewrite();
    } on EmptySourceError {
      if (!mounted) return;
      showAppSnackBar('Nothing to rewrite yet.');
    } on ModelNotInstalledException {
      if (!mounted) return;
      TabNavigator.of(context).goToTab(AppTab.models);
    } on EngineException catch (e) {
      if (!mounted) return;
      final fallback = controller.pendingFallback;
      if (fallback != null) {
        await _offerFallback(controller, fallback);
        return;
      }
      showAppSnackBar(describeEngineError(e));
    }
  }

  /// Reacts to a Hybrid-mode fallback `rewrite()` just offered.
  ///
  /// Cloud→local never needs asking (see `RewriteController.pendingFallback`'s
  /// own doc) and retries immediately. Local→cloud sends text the user never
  /// explicitly chose to send off-device, so it asks first, naming the
  /// provider and model in full.
  Future<void> _offerFallback(RewriteController controller, EngineTarget fallback) async {
    if (!controller.pendingFallbackNeedsConsent) {
      await _retryFallback(controller);
      return;
    }

    final providerId = fallback.providerId;
    final provider = providerId == null
        ? null
        : context.read<ProviderRegistry>().byId(providerId);
    final label = provider?.displayName ?? 'the cloud provider';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send to the cloud instead?'),
        content: Text(
          'The on-device rewrite failed. Send this text to $label '
          '(${fallback.modelRef}) instead?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Send once'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmed == true) {
      await _retryFallback(controller);
    } else {
      controller.dismissFallback();
    }
  }

  Future<void> _retryFallback(RewriteController controller) async {
    try {
      await controller.retryWithFallback();
    } on EngineException catch (e) {
      if (!mounted) return;
      showAppSnackBar(describeEngineError(e));
    }
  }
}

class _SourceInput extends StatefulWidget {
  const _SourceInput();

  @override
  State<_SourceInput> createState() => _SourceInputState();
}

class _SourceInputState extends State<_SourceInput> {
  late final TextEditingController _text = TextEditingController(
    text: context.read<RewriteController>().sourceText,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _syncFromState() {
    final external = context.read<RewriteController>().sourceText;
    if (external != _text.text) {
      _text.value = TextEditingValue(
        text: external,
        selection: TextSelection.collapsed(offset: external.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RewriteController>();
    _syncFromState();

    return Semantics(
      identifier: 'rewrite_input',
      child: TextField(
        controller: _text,
        onChanged: controller.setSource,
        minLines: 3,
        maxLines: 10,
          maxLength: 8000,
          buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$currentLength/${maxLength ?? 8000}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          labelText: 'Text to rewrite',
          hintText: 'Type or paste your rough text here…',
          alignLabelWithHint: true,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                identifier: 'rewrite_input_paste',
                child: IconButton(
                  tooltip: 'Paste',
                  onPressed: () => _paste(controller),
                  icon: const Icon(Icons.content_paste_go_outlined),
                ),
              ),
              if (controller.sourceText.isNotEmpty)
                Semantics(
                  identifier: 'rewrite_input_clear',
                  child: IconButton(
                    tooltip: 'Clear',
                    onPressed: () => controller.setSource(''),
                    icon: const Icon(Icons.close),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _paste(RewriteController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isNotEmpty) {
      controller.setSource(text);
    }
  }
}

class _InstructionInput extends StatefulWidget {
  const _InstructionInput({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_InstructionInput> createState() => _InstructionInputState();
}

class _InstructionInputState extends State<_InstructionInput> {
  late final TextEditingController _text = TextEditingController(
    text: widget.value,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_text.text != widget.value) {
      _text.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
    return Semantics(
      identifier: 'rewrite_instruction_input',
      child: TextField(
        controller: _text,
        onChanged: widget.onChanged,
        decoration: const InputDecoration(
          labelText: 'Extra instructions',
          hintText: 'e.g. Make it sound more optimistic',
          prefixIcon: Icon(Icons.edit_note_outlined),
        ),
      ),
    );
  }
}

class _AudienceSelector extends StatelessWidget {
  const _AudienceSelector({required this.selected, required this.onToggle});

  /// Audience *ids* — see `RewriteController.toggleAudience`'s own doc for
  /// why this is an id list, not a label list.
  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final audiences = context.watch<ConfigStore>().audiences;
    return SizedBox(
      width: double.infinity,
      child: Semantics(
        container: true,
        identifier: 'audience_selector',
        child: Wrap(
          alignment: WrapAlignment.start,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final audience in audiences)
              Semantics(
                identifier: 'audience_option_${audience.id}',
                child: FilterChip(
                  label: Text(audience.label),
                  selected: selected.contains(audience.id),
                  onSelected: (_) => onToggle(audience.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RewriteButton extends StatelessWidget {
  const _RewriteButton({
    required this.running,
    required this.cancelling,
    required this.onRewrite,
    required this.onStop,
  });

  final bool running;
  final bool cancelling;
  final VoidCallback onRewrite;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Semantics(
        identifier: 'rewrite_button',
        child: FilledButton.icon(
          onPressed: cancelling
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  if (running) {
                    onStop();
                  } else {
                    onRewrite();
                  }
                },
          icon: running
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_fix_high),
          label: Text(
            cancelling ? 'Stopping…' : (running ? 'Stop rewrite' : 'Rewrite'),
          ),
        ),
      ),
    );
  }
}

class _StreamingPanel extends StatelessWidget {
  const _StreamingPanel({
    required this.text,
    required this.stage,
    required this.capabilities,
    required this.cancelling,
  });

  final String text;
  final EngineStage stage;
  final EngineCapabilities capabilities;
  final bool cancelling;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    cancelling
                        ? 'Stopping the current rewrite…'
                        : stageLabel(stage, capabilities),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (!cancelling &&
                stage == EngineStage.preparing &&
                capabilities.needsLocalInstall) ...[
              const SizedBox(height: 8),
              Text(
                'First run after opening the app reads the whole model into '
                'memory. This is the slow part — later rewrites reuse it.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (text.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                text,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown while a `ShareIntentBridge.awaitingProcessTextResult` request is
/// live — the text below came from another app's selection toolbar, and
/// once a rewrite finishes, an "Insert & return" action appears alongside
/// the result to hand it back and close this screen. Nothing here forces
/// that path: the rewrite still behaves like any other, and the user can
/// just navigate away, which Android reads as declining (see
/// `MainActivity.kt`'s own doc for why that needs no extra code).
class _ProcessTextBanner extends StatelessWidget {
  const _ProcessTextBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.text_fields_outlined, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Rewrite this, then tap "Insert & return" to send it back.',
              style: TextStyle(color: scheme.onTertiaryContainer, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Replaces the old `_ModelMissingBanner`, which had two bugs beyond its
/// copy: it rendered purely from `models.isInstalled(...)` with no
/// capability check at all, so it could appear over a perfectly working
/// cloud rewrite once Cloud/Hybrid mode existed; and its copy ("Everything
/// runs on your phone. No accounts, no cloud.") was only ever true on the
/// local branch. This is driven by `RoutingDecision.blocker` instead, with
/// a route to the actual fix per case.
class _TargetNotReadyBanner extends StatelessWidget {
  const _TargetNotReadyBanner({required this.blocker});

  final RoutingBlocker blocker;

  (String, String, IconData) get _copy => switch (blocker) {
    RoutingBlocker.noLocalModel => (
      'First step: install an AI model',
      'On-device rewriting needs a model downloaded to this phone.',
      Icons.download_done_outlined,
    ),
    RoutingBlocker.noCloudProvider => (
      'Add a cloud provider',
      'Cloud rewriting needs at least one provider set up with an API key.',
      Icons.cloud_outlined,
    ),
    RoutingBlocker.cloudDisabledByPolicy => (
      'Cloud rewriting is turned off',
      'Enable it in Privacy settings, or switch to Local mode.',
      Icons.privacy_tip_outlined,
    ),
  };

  void _onTap(BuildContext context) {
    switch (blocker) {
      case RoutingBlocker.noLocalModel:
        TabNavigator.of(context).goToTab(AppTab.models);
      case RoutingBlocker.noCloudProvider:
        Navigator.of(context).pushNamed(AppRoutes.providers);
      case RoutingBlocker.cloudDisabledByPolicy:
        Navigator.of(context).pushNamed(AppRoutes.privacy);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (title, subtitle, icon) = _copy;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _onTap(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: scheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: scheme.onPrimaryContainer)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

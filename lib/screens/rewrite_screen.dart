import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../engine/engine_capabilities.dart';
import '../engine/engine_error_messages.dart';
import '../engine/engine_exception.dart';
import '../engine/engine_stage.dart';
import '../services/config_store.dart';
import '../state/models_controller.dart';
import '../state/rewrite_controller.dart';
import '../widgets/mic_button.dart';
import '../widgets/result_view.dart';
import '../widgets/rewrite_controls.dart';
import '../widgets/tone_selector.dart';

/// The core "type, pick a tone, rewrite" screen.
class RewriteScreen extends StatefulWidget {
  const RewriteScreen({super.key, required this.onGoToModels});

  final VoidCallback onGoToModels;

  @override
  State<RewriteScreen> createState() => _RewriteScreenState();
}

class _RewriteScreenState extends State<RewriteScreen> {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RewriteController>();
    final models = context.watch<ModelsController>();

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
          if (controller.isRunning)
            IconButton(
              tooltip: 'Stop',
              onPressed: controller.isCancelling ? null : controller.stop,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            if (!models.isInstalled(models.selectedModelId) && !models.scanning)
              _ModelMissingBanner(onTap: widget.onGoToModels),
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
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1')),
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 3, label: Text('3')),
              ],
              selected: {controller.variantCount},
              onSelectionChanged: (s) => controller.setVariantCount(s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 24),
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
              ResultView(result: controller.lastResult!),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _rewrite(controller),
                icon: const Icon(Icons.refresh),
                label: const Text('Rewrite again'),
              ),
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

  Future<void> _rewrite(RewriteController controller) async {
    FocusScope.of(context).unfocus();
    try {
      await controller.rewrite();
    } on EmptySourceError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to rewrite yet.')),
      );
    } on ModelNotInstalledException {
      if (!mounted) return;
      widget.onGoToModels();
    } on EngineException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(describeEngineError(e))));
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

    return TextField(
      controller: _text,
      onChanged: controller.setSource,
      minLines: 5,
      maxLines: 12,
      maxLength: 8000,
      textInputAction: TextInputAction.newline,
      decoration: InputDecoration(
        labelText: 'Text to rewrite',
        hintText: 'Type or paste your rough text here…',
        alignLabelWithHint: true,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Paste',
              onPressed: () => _paste(controller),
              icon: const Icon(Icons.content_paste_go_outlined),
            ),
            if (controller.sourceText.isNotEmpty)
              IconButton(
                tooltip: 'Clear',
                onPressed: () => controller.setSource(''),
                icon: const Icon(Icons.close),
              ),
          ],
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
    return TextField(
      controller: _text,
      onChanged: widget.onChanged,
      decoration: const InputDecoration(
        labelText: 'Extra instructions',
        hintText: 'e.g. Make it sound more optimistic',
        prefixIcon: Icon(Icons.edit_note_outlined),
      ),
    );
  }
}

class _AudienceSelector extends StatelessWidget {
  const _AudienceSelector({required this.selected, required this.onToggle});

  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final audiences = context.watch<ConfigStore>().audiences;
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.start,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final audience in audiences)
            FilterChip(
              label: Text(audience.label),
              selected: selected.contains(audience.label),
              onSelected: (_) => onToggle(audience.label),
            ),
        ],
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
      child: FilledButton.icon(
        onPressed: cancelling ? null : (running ? onStop : onRewrite),
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

class _ModelMissingBanner extends StatelessWidget {
  const _ModelMissingBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                Icons.download_done_outlined,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'First step: install an AI model',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Everything runs on your phone. No accounts, no cloud.',
                      style: TextStyle(color: scheme.onPrimaryContainer),
                    ),
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

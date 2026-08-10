import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/speech_controller.dart';

/// Large microphone button for voice input.
///
/// Tap to start, tap again to finish. Shows an animated pulse while
/// recording. If the platform has no on-device speech support yet, it
/// explains that clearly.
class MicButton extends StatefulWidget {
  const MicButton({super.key, this.size = 84, this.onResult, this.onError});

  final double size;

  /// Called with the final transcript when dictation completes.
  final ValueChanged<String>? onResult;

  final ValueChanged<String>? onError;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SpeechController>();
    final isRecording = controller.isRecording;
    final phase = controller.phase;
    final canTap = phase == SpeechPhase.idle || phase == SpeechPhase.recording;
    final scheme = Theme.of(context).colorScheme;

    if (isRecording) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.reset();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final t = isRecording ? 1.0 + (_pulse.value * 0.35) : 1.0;
            final opacity = isRecording ? (1 - _pulse.value) * 0.35 : 0.0;
            final pulseSize = widget.size * 1.35;
            return SizedBox(
              width: pulseSize,
              height: pulseSize,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (isRecording)
                    Container(
                      width: widget.size * t,
                      height: widget.size * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.error.withValues(alpha: opacity),
                      ),
                    ),
                  Semantics(
                    button: true,
                    enabled: canTap,
                    label: isRecording
                        ? 'Stop recording and transcribe'
                        : 'Start voice dictation',
                    value: _phaseLabel(phase, controller.downloadSize),
                    child: Material(
                      shape: const CircleBorder(),
                      color: isRecording ? scheme.error : scheme.primary,
                      elevation: 6,
                      shadowColor: scheme.primary.withValues(alpha: 0.4),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: !canTap
                            ? null
                            : isRecording
                            ? () => _stop(context)
                            : () => _start(context),
                        child: SizedBox(
                          width: widget.size,
                          height: widget.size,
                          child: Icon(
                            isRecording ? Icons.stop : Icons.mic,
                            color: scheme.onPrimary,
                            size: widget.size * 0.42,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          _phaseLabel(phase, controller.downloadSize),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (phase == SpeechPhase.initializing ||
            phase == SpeechPhase.downloadingModel ||
            phase == SpeechPhase.transcribing) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: 180,
            child: LinearProgressIndicator(
              value: controller.progress > 0 ? controller.progress : null,
            ),
          ),
          if (phase == SpeechPhase.downloadingModel) ...[
            const SizedBox(height: 6),
            Text(
              'One-time download · keep this screen open',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
        if (controller.lastError.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              controller.lastError,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _start(BuildContext context) async {
    final controller = context.read<SpeechController>();
    await controller.start();
    if (controller.lastError.isNotEmpty) {
      widget.onError?.call(controller.lastError);
    }
  }

  Future<void> _stop(BuildContext context) async {
    final controller = context.read<SpeechController>();
    if (!controller.isRecording) return;
    final result = await controller.stopAndTranscribe();
    if (!mounted) return;
    if (result.text.isNotEmpty) {
      widget.onResult?.call(result.text);
    }
  }

  String _phaseLabel(SpeechPhase phase, String downloadSize) => switch (phase) {
    SpeechPhase.idle => 'Tap to dictate',
    SpeechPhase.requestingPermission => 'Checking microphone access…',
    SpeechPhase.downloadingModel => downloadSize.isEmpty
        ? 'Downloading the voice model…'
        : 'Downloading the voice model ($downloadSize)…',
    SpeechPhase.initializing => 'Preparing voice input…',
    SpeechPhase.recording => 'Tap to stop',
    SpeechPhase.transcribing => 'Creating transcript…',
  };
}

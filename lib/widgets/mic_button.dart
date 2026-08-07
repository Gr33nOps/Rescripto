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
  const MicButton({
    super.key,
    this.size = 84,
    this.onResult,
    this.onError,
  });

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
    final isBusy = controller.isBusy;
    final scheme = Theme.of(context).colorScheme;

    if (isRecording) {
      _pulse.repeat();
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
            return SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
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
                  Material(
                    shape: const CircleBorder(),
                    color: isRecording ? scheme.error : scheme.primary,
                    elevation: 6,
                    shadowColor: scheme.primary.withValues(alpha: 0.4),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: isBusy ? () => _stop(context) : () => _start(context),
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
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          isBusy
              ? (isRecording ? 'Tap to stop' : 'Listening…')
              : 'Tap to dictate',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        if (controller.lastError.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              controller.lastError,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _start(BuildContext context) async {
    final controller = context.read<SpeechController>();
    if (!controller.isSupported) {
      widget.onError?.call(
          'On-device voice input is not available on this platform yet. '
          'Android is currently supported.');
      return;
    }
    await controller.start();
    if (controller.lastError.isNotEmpty) {
      widget.onError?.call(controller.lastError);
    }
  }

  Future<void> _stop(BuildContext context) async {
    final controller = context.read<SpeechController>();
    if (!controller.isRecording) {
      await controller.cancel();
      return;
    }
    final result = await controller.stopAndTranscribe();
    if (!mounted) return;
    if (result.text.isNotEmpty) {
      widget.onResult?.call(result.text);
    }
  }
}

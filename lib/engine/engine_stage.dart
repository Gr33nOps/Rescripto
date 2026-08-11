import 'engine_capabilities.dart';

/// Where a running generation currently is.
///
/// Deliberately engine-neutral: unlike the `RewriteStage` it replaces, nothing
/// here says "model" or "device". A cloud engine reports the same stages a
/// local one does; only the [EngineCapabilities]-driven label in
/// [stageLabel] differs.
enum EngineStage { preparing, submitting, streaming, finalizing }

/// User-facing text for [stage], adapted to what [capabilities] describes.
///
/// Loading a multi-hundred-megabyte model takes real time on a phone, and a
/// bare spinner for it is what makes the app look hung — so `preparing` earns
/// its own copy when [EngineCapabilities.needsLocalInstall] is true. A cloud
/// engine has no such wait, so it gets generic copy instead.
String stageLabel(EngineStage stage, EngineCapabilities capabilities) =>
    switch (stage) {
      EngineStage.preparing => capabilities.needsLocalInstall
          ? 'Loading the AI model…'
          : 'Getting ready…',
      EngineStage.submitting => capabilities.requiresNetwork
          ? 'Sending to the provider…'
          : 'Reading your text…',
      EngineStage.streaming => capabilities.needsLocalInstall
          ? 'Rewriting on your device…'
          : 'Rewriting…',
      EngineStage.finalizing => 'Finishing up…',
    };

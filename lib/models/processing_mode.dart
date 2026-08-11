/// Where a rewrite (or transcription) is allowed to run.
enum ProcessingMode {
  /// On-device only. The default, and the only mode that needs no network
  /// permission to be meaningful.
  local,

  /// Cloud only. `TargetRouter` still returns a blocker if nothing is
  /// configured — this mode never silently falls back to local.
  cloud,

  /// Whichever of local or cloud is actually usable, chosen by
  /// `TargetRouter` on three explainable inputs: cloud availability, local
  /// availability, and input length.
  hybrid,
}

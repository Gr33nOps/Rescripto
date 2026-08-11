/// A distinct reason the app might reach the network, each independently
/// switchable in [NetworkPolicy].
///
/// Only [modelDownload] and [voiceModelDownload] have a caller today; the
/// other four exist so the policy vocabulary — and its default of "off until
/// the user opts in" for anything that isn't already app's existing
/// behavior — doesn't need a breaking shape change the day a cloud engine or
/// sync actually lands.
enum NetworkFeature {
  /// Downloading a GGUF model (`ModelManager`).
  modelDownload,

  /// Downloading a whisper.cpp voice model (`flutter_whisper`'s downloader).
  voiceModelDownload,

  /// A cloud rewrite provider (Phase 2). Not wired to a caller yet.
  cloudRewrite,

  /// A cloud speech-to-text provider (Phase 2). Not wired to a caller yet.
  cloudSpeech,

  /// Encrypted backup / WebDAV sync (Phase 4). Not wired to a caller yet.
  sync,

  /// Checking for a new app release. Not wired to a caller yet.
  updateCheck,
}

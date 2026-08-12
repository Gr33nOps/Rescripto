/// A distinct reason the app might reach the network, each independently
/// switchable in [NetworkPolicy].
///
/// Every member except [updateCheck] now has a real caller. The enum was
/// written ahead of them on purpose, so the policy vocabulary — and its
/// default of "off until the user opts in" for anything that wasn't already
/// the app's existing behaviour — never needed a breaking shape change as
/// each one landed.
enum NetworkFeature {
  /// Downloading a GGUF model (`ModelManager`).
  modelDownload,

  /// Downloading a whisper.cpp voice model (`flutter_whisper`'s downloader).
  voiceModelDownload,

  /// A cloud rewrite provider (`CloudRewriteEngine`).
  cloudRewrite,

  /// A cloud speech-to-text provider (`CloudSpeechEngine`).
  cloudSpeech,

  /// Encrypted backup / WebDAV sync (`SyncService`).
  sync,

  /// Checking for a new app release. Not wired to a caller yet.
  updateCheck,
}

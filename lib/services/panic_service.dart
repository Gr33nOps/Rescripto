import 'credentials/credential_store.dart';
import 'network/network_policy.dart';

/// What [PanicService.wipeCredentials] actually did, for the UI to report.
class PanicReport {
  const PanicReport({required this.credentialsWiped, required this.networkDisabled});

  /// Number of indexed credentials removed.
  final int credentialsWiped;

  /// Whether the network kill switch is now on.
  final bool networkDisabled;
}

/// Emergency key removal (§13): one call that gets every stored secret off
/// the device and stops the app from reaching the network at all.
///
/// Ordered and safe to call more than once. The kill switch goes on *first*
/// — before anything is deleted — so a request already retrying in the
/// background can't complete using a key that's about to vanish partway
/// through the wipe. Must work fully offline; nothing here touches the
/// network itself.
///
/// Scoped to what exists today: there is no in-flight cloud request to
/// cancel and no `ProviderConfig` to disable, because no cloud engine has
/// been built yet (Phase 2). This class does the two things Phase 1 has
/// state for — network access and stored secrets — rather than reaching for
/// hooks with nothing on the other end. Cancelling in-flight cloud work and
/// disabling provider configs belong here too once Phase 2 gives them
/// something real to act on.
class PanicService {
  PanicService(this._credentialStore, this._networkPolicy);

  final CredentialStore _credentialStore;
  final NetworkPolicy _networkPolicy;

  Future<PanicReport> wipeCredentials() async {
    await _networkPolicy.setKillSwitch(true);
    final wiped = await _credentialStore.deleteAll();
    return PanicReport(credentialsWiped: wiped, networkDisabled: true);
  }
}

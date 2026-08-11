import '../engine/active_request_registry.dart';
import 'credentials/credential_store.dart';
import 'network/network_policy.dart';
import 'providers/provider_registry.dart';

/// What [PanicService.wipeCredentials] actually did, for the UI to report.
class PanicReport {
  const PanicReport({
    required this.credentialsWiped,
    required this.networkDisabled,
    required this.providersDisabled,
    required this.requestsCancelled,
  });

  /// Number of indexed credentials removed.
  final int credentialsWiped;

  /// Whether the network kill switch is now on.
  final bool networkDisabled;

  /// Number of provider configs turned off.
  final int providersDisabled;

  /// Number of in-flight requests cancelled.
  final int requestsCancelled;
}

/// Emergency key removal (§13): one call that gets every stored secret off
/// the device, stops the app from reaching the network at all, disables
/// every cloud provider, and cancels whatever's already in flight.
///
/// Ordered and safe to call more than once, and it has to be: the kill
/// switch goes on *first*, before anything else, so a request already
/// retrying in the background can't complete using a key that's about to
/// vanish partway through the wipe. In-flight requests are cancelled next —
/// `ActiveRequestRegistry` is the only thing that can actually reach an
/// already-open stream, since flipping the kill switch alone only blocks
/// requests that haven't started yet. Must work fully offline; nothing here
/// touches the network itself.
class PanicService {
  PanicService(
    this._credentialStore,
    this._networkPolicy,
    this._providerRegistry,
    this._activeRequests,
  );

  final CredentialStore _credentialStore;
  final NetworkPolicy _networkPolicy;
  final ProviderRegistry _providerRegistry;
  final ActiveRequestRegistry _activeRequests;

  Future<PanicReport> wipeCredentials() async {
    await _networkPolicy.setKillSwitch(true);
    final requestsBefore = _activeRequests.activeCount;
    await _activeRequests.cancelAll();
    final providersBefore = _providerRegistry.enabledConfigs.length;
    await _providerRegistry.disableAll();
    final wiped = await _credentialStore.deleteAll();
    return PanicReport(
      credentialsWiped: wiped,
      networkDisabled: true,
      providersDisabled: providersBefore,
      requestsCancelled: requestsBefore,
    );
  }
}

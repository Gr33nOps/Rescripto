ID:               CLOUD-PROVIDER-STALE-KEY-001
Severity:         Medium
Area:             Settings > Cloud providers
Feature:          The provider list's "No key" / "•••• configured" status,
                   shown immediately after adding a provider with an API
                   key
Device/API:       Rescripto_Test, Android 15 (API 35), x86_64 emulator
App build/commit: debug APK built from HEAD `2365240`
                   ("Bump version to 1.1.1 for release") during this QA
                   pass
Preconditions:    None. Tested with a real Groq API key provided by the
                   project owner for this QA pass (not committed, not
                   logged anywhere).
Steps to reproduce:
  1. Settings > Cloud providers > Add provider > Groq.
  2. Type a real API key into the API key field.
  3. Tap "Add provider" (save).
Expected behavior:
  Back on the Cloud providers list, the new "Groq" row shows
  "Groq · •••• configured" — the key was typed and saved.
Actual behavior:
  The row shows "Groq · No key" — as if the key was never entered. Nothing
  in the UI indicates the save actually failed (no error, no SnackBar), and
  in fact **it didn't fail** — reopening the same provider's edit screen
  shows a "Remove saved key" icon on the API key field (only rendered when
  a key is genuinely stored) and "Test connection" gives "Cloud rewriting
  is turned off..." rather than the true no-key message ("This provider
  isn't set up yet. Add an API key in Providers to use it."), proving the
  key really is stored. The list is simply lying. It stays wrong
  indefinitely — navigating to a *different* Settings screen (Privacy &
  network) and back was enough to make it self-correct to
  "Groq · •••• configured", but nothing about that navigation should have
  mattered.
Reproducibility: Always (the underlying ordering bug always occurs); the
  precise moment it visibly self-corrects depends on when some unrelated
  screen happens to force a rebuild, which is not something a user would
  know to do.
Screenshot/video:
  testing/mobile/screenshots/cloud_provider_stale_no_key_20260813_004604.png
  (list immediately after saving — wrong)
  testing/mobile/screenshots/cloud_provider_edit_has_remove_key_20260813_004745.png
  (same provider's edit screen — "Remove saved key" present, proving the
  key is real)
  testing/mobile/screenshots/cloud_provider_configured_after_revisit_20260813_005021.png
  (list after visiting an unrelated screen and returning — self-corrected)
Relevant logs:    N/A — no exception, no crash; a pure stale-read bug.
Suspected cause:  `lib/screens/provider_edit_screen.dart`'s `_save()`
                   (around line 213-260) does, in order:
                       await registry.save(config);       // line 243
                       ...
                       await credentialStore.write(credential, typedKey);  // line 247
                   `registry.save()` is a `ProviderRegistry` (ChangeNotifier)
                   mutation and fires `notifyListeners()` as part of
                   completing — which schedules a rebuild of
                   `ProvidersScreen` (it does `context.watch<ProviderRegistry>()`
                   at `lib/screens/providers_screen.dart:24`) *before* the
                   API key has actually been written anywhere.
                   `_ProviderTile` (same file, ~line 226-255) queries the
                   key's presence directly in `build()`:
                       subtitle: FutureBuilder<bool>(
                         future: credentialStore.has(config.credential),
                         ...
                       ),
                   Because this `Future` is created fresh every `build()`
                   call rather than cached/watched, whichever `build()`
                   happens to run first captures whatever `has()` returns
                   *at that instant* — and if that instant is the rebuild
                   triggered by `registry.save()`'s notification, the key
                   write (line 247) hasn't happened yet, so `has()`
                   correctly-at-the-time returns `false`. `CredentialStore`
                   is a plain class, not a `ChangeNotifier`
                   (`lib/services/credentials/credential_store.dart`), so
                   nothing tells `_ProviderTile` to re-query once the write
                   actually lands a moment later — the tile is stuck with
                   its first (wrong) answer until something *else*
                   coincidentally triggers `ProvidersScreen` to rebuild.
                   Fix shape: reorder `_save()` to write the credential
                   *before* saving the provider config (or await both, then
                   fire one combined notification), so the first rebuild
                   the list sees already reflects the correct key state.

Regression test: not added. I wrote one
(`test/providers_screen_test.dart`, since removed) that drove the exact
real add-provider flow end to end against a real temp-file `AppDatabase`
+ `FakeSecureStorage`, and it reliably demonstrated the race existed in
principle — but `sqflite_common_ffi`'s background-isolate I/O doesn't
resolve inside `testWidgets()`'s fake-async zone without manual
`tester.runAsync()` stepping, and the *exact* number/size of those steps
determines whether the test observes the stale read or the (also real,
also order-dependent) self-correcting rebuild from the route-pop
transition completing. That makes the window itself timing-sensitive
enough that I could not get a deterministic pass/fail without hand-tuning
sleep durations to match this one environment, which would be a flaky
test dressed as a regression test. The bug itself is real and directly
observed on-device (see screenshots and the code trace above); a reliable
regression test would need either a fake/injectable clock for
`CredentialStore`/`ProviderRegistry` or restructuring `_save()`'s await
order first, whichever is fixed, then a test asserting the new order can
be written directly against the corrected code.

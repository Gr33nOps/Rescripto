ID:               WEBDAV-SYNC-SILENT-FAIL-001
Severity:         Medium
Area:             Settings > Backup > WebDAV sync
Feature:          "Sync now" button (`sync_button`) on the WebDAV sync screen
Device/API:       Rescripto_Test, Android 15 (API 35), x86_64 emulator
App build/commit: debug APK built from HEAD `2365240`
                   ("Bump version to 1.1.1 for release") during this QA pass
Preconditions:    A WebDAV server configured (server URL + username + saved
                   password) in Settings > Backup > WebDAV sync. The
                   "Backup sync" toggle in Settings > Privacy & network is in
                   its **default (off)** state.
Steps to reproduce:
  1. Settings > Cloud providers... (not needed)  -  Settings > Backup > WebDAV
     sync. Fill in Server URL / Username, tap "Set server password", enter a
     password, Save.
  2. Do NOT enable "Backup sync" in Privacy & network (leave it at its
     shipped default: off).
  3. Tap "Sync now".
Expected behavior:
  Either the button is disabled/explained when the feature is off (the way
  Processing-mode banners explain "add a cloud provider" per the test plan),
  or tapping it shows a clear error such as "Backup sync is turned off -
  enable it in Privacy & network to sync," matching the pattern already used
  elsewhere in the app for blocked actions.
Actual behavior:
  Nothing happens. No SnackBar, no dialog, no inline error text, no change
  to the "Last pushed: ..." status line. The screen is pixel-identical
  before and after the tap (compare
  `webdav_sync_silent_fail_20260813_005927.png`  -  the "Last pushed" caption
  never advances). The failure is only discoverable by digging into
  Settings > Privacy & network > Network log, which does correctly record
  it as "Sync backup · Blocked (Privacy setting)"
  (`webdav_network_log_evidence_20260813_005927.png`)  -  but almost no real
  user would think to look there after a silently-ignored button tap.
  Root cause confirmed in logcat: an **unhandled** exception is thrown and
  swallowed by Flutter's default zone error handler, so the UI layer never
  gets a chance to react:
    Unhandled Exception: NetworkBlockedByPolicyException(sync, featureDisabled)
    #0  GuardedHttpClient.send (package:rescripto/services/network/network_guard.dart:214:7)
    #1  BaseClient._sendUnstreamed (package:http/src/base_client.dart:93:32)
    #2  WebDavClient.put (package:rescripto/services/sync/webdav_client.dart:27:22)
    #3  SyncService.push (package:rescripto/services/sync/sync_service.dart:116:5)
    #4  _SyncScreenState._push (package:rescripto/screens/backup/sync_screen.dart:308:7)
  `_SyncScreenState._push` does not catch `NetworkBlockedByPolicyException`
  around its call into `SyncService.push`, so the exception propagates all
  the way out uncaught. This is the same *shape* of bug already reported in
  PROVIDER-001's "Workflow > Add step" finding (an exception thrown from a
  button callback, outside `build()`, is silently eaten by the zone handler
  with zero UI signal)  -  but it is a different root cause and a different
  code path (network policy guard vs. mis-registered `Provider`), so it is
  filed separately here.

  For contrast: when "Backup sync" IS enabled, the feature works correctly
  and *does* give good feedback  -  a persistent "Last pushed: <timestamp>"
  status line, and a "The server has a newer copy (...) [Review and apply]"
  conflict banner when the remote copy is newer. Confirmed via a real sync
  against the WebDAV test server (two successful `PUT` "HTTP 201" round
  trips visible in the Network log). So this is specifically a gap in the
  *failure* path, not a general absence of sync status UI.
Reproducibility: Always (confirmed twice  -  once from the feature's true
  default state, once again after deliberately re-disabling it).
Screenshot/video:
  testing/mobile/screenshots/webdav_sync_silent_fail_20260813_005927.png
  (WebDAV sync screen immediately after the no-op "Sync now" tap  -  compare
  timestamp/state to any earlier screenshot of the same screen, identical)
  testing/mobile/screenshots/webdav_network_log_evidence_20260813_005927.png
  (Network log showing the same action correctly recorded as
  "Sync backup · Blocked (Privacy setting)", proving the app *does* know
  why it failed  -  that information just never reaches the sync screen's UI)
Relevant logs:    testing/mobile/logs/logcat_20260813_003247.txt (first
  occurrence, ~00:31:48), testing/mobile/logs/logcat_20260813_004122.txt
  (second occurrence, ~00:34:56)  -  search for "NetworkBlockedByPolicyException"
Suspected cause:  `lib/screens/backup/sync_screen.dart:308`, `_push()`,
  calls `SyncService.push(...)` without a `try`/`catch` around the
  `NetworkBlockedByPolicyException` that `GuardedHttpClient.send` (in
  `lib/services/network/network_guard.dart:214`) throws when the relevant
  per-feature network toggle is off. Every other blocked-feature path in
  this app (Local-mode-without-a-model banner, Cloud-without-a-provider
  banner, etc.) surfaces a specific, actionable message; this one path does
  not. Fix shape: wrap the `SyncService.push`/`pull` calls in `_push`/`_pull`
  (sync_screen.dart) in a catch for `NetworkBlockedByPolicyException` and
  show a SnackBar naming the disabled feature and pointing at Privacy &
  network, mirroring the existing banner pattern used elsewhere.

Regression test: not added. This is a UI-feedback gap in a widget's
  error-handling flow (a missing catch clause around an async call in a
  screen's button handler), not a pure logic bug in a model/store/
  controller, so per the QA plan's guidance it's better suited to a
  targeted widget test once the fix lands (pump `SyncScreen` with a fake
  `SyncService` that throws `NetworkBlockedByPolicyException`, assert a
  SnackBar/error appears) rather than a test written against the current,
  intentionally-wrong behavior.

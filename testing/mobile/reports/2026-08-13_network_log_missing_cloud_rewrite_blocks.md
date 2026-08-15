ID:               NETLOG-MISSING-CLOUD-BLOCK-001
Severity:         Low
Area:             Privacy & network / Network log
Feature:          Network log completeness vs. Privacy toggle / kill switch enforcement
Device/API:       Rescripto_Test, Android 15 (API 35), arm64-v8a APK on x86_64 emulator
App build/commit: 2365240
Preconditions:    Groq cloud provider configured and enabled; Processing mode = Cloud; Pro mode with existing input text.
Steps to reproduce:
  1. Settings -> Privacy & network -> turn OFF "Cloud rewriting".
  2. Go to Rewrite screen (Cloud target correctly shows "Not ready" pill).
  3. Tap Rewrite. A snackbar correctly reports "That processing target isn't
     available right now. Check your processing mode in Settings."
  4. Open Settings -> Privacy & network -> Network log (pull to refresh).
  5. Repeat with the master "Network kill switch" toggled ON instead (step 1
     variant) and Cloud rewriting re-enabled.
Expected behavior: Network log's own description states "This shows every
  request made through this app's network guard ... " and blocked WebDAV
  sync attempts do appear there as "Blocked (Privacy setting)" rows. A user
  would reasonably expect a blocked cloud-rewrite attempt to appear the same
  way, as evidence the privacy control actually did something.
Actual behavior: No entry is added to the Network log for either the
  Cloud-rewriting-toggle-off block or the kill-switch block. Root cause
  (confirmed via source): `TargetRouter._cloudTarget`
  (lib/services/routing/target_router.dart:141-148) checks
  `networkPolicy.killSwitch` / `isAllowed(NetworkFeature.cloudRewrite)`
  synchronously and returns `target: null` before `RewriteController` ever
  calls `CloudRewriteEngine`/`NetworkGuard.dioFor(...)`. Since the request
  never reaches `_GuardInterceptor.onRequest` (network_guard.dart:94-131),
  `log.record(...)` is never invoked for these blocks. This is the opposite
  of WebDAV's `SyncService`, which does dispatch its guarded request
  regardless of the toggle, so the guard's own block+log path fires (see
  WEBDAV-SYNC-SILENT-FAIL-001  -  that bug is the reverse problem: WebDAV logs
  the block but shows no in-app feedback; cloud rewrite shows a clear
  snackbar but leaves no log record).
Reproducibility:  Always (2/2 attempts: toggle-off and kill-switch)
Screenshot/video: testing/mobile/screenshots/44_privacy_cloud_rewrite_off_blocked_snackbar_20260813.png,
                   testing/mobile/screenshots/45_privacy_kill_switch_blocked_snackbar_20260813.png,
                   testing/mobile/screenshots/46_network_log_no_cloud_entries_20260813.png
Relevant logs:    Confirmed via `adb logcat` grep for "groq"/"api.groq" around both
                   attempts  -  zero matches, corroborating no HTTP call was even
                   attempted (expected, given the pre-flight block), but this
                   also means there is no log evidence anywhere, in-app or
                   logcat, that the block happened except the transient snackbar.
Suspected cause:  lib/services/routing/target_router.dart:92-93,141-148 blocks
                   pre-flight, bypassing lib/services/network/network_guard.dart's
                   logging interceptor entirely for this feature.

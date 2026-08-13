ID:               PROCESSING-INDICATOR-STALE-001
Severity:         Medium
Area:             Rewrite screen / Privacy & network interaction
Feature:          `ProcessingIndicator` AppBar pill + the "Cloud rewriting is
                   turned off" warning banner on the Rewrite screen
Device/API:       Rescripto_Test, Android 15 (API 35), arm64-v8a APK on x86_64 emulator
App build/commit: 2365240
Preconditions:    Processing mode = Cloud, a working enabled Groq provider
                   configured, Pro or Simple mode, Rewrite screen already
                   visited at least once this app session (so its state is
                   alive in the tab `IndexedStack`).
Steps to reproduce:
  1. On the Rewrite screen, confirm the AppBar pill reads "Cloud" (ready).
  2. Settings -> Privacy & network -> turn OFF "Cloud rewriting". Go back to
     Rewrite tab. Pill correctly flips to "Not ready" and a banner reads
     "Cloud rewriting is turned off. Enable it in Privacy settings, or
     switch to Local mode." (this half works correctly).
  3. Settings -> Privacy & network -> turn "Cloud rewriting" back ON.
  4. Go straight back to the Rewrite tab. Do **not** type in the source
     field, change any tone/intensity/audience control, or tap Rewrite.
  5. Observe the AppBar pill and the warning banner.
Expected behavior: The pill should read "Cloud" and the "Cloud rewriting is
  turned off" banner should be gone, matching the Privacy screen's now-ON
  toggle.
Actual behavior: The pill still reads "Not ready" and the stale "Cloud
  rewriting is turned off" banner is still shown, even though the toggle is
  confirmed ON on the Privacy screen. The stale state persists indefinitely
  across tab switches — it only self-corrects the instant something else
  touches `RewriteController`'s own state, e.g. typing a single character
  into the source field immediately flips the pill to "Cloud" and removes
  the banner (confirmed: typing "a" fixed it in the same test run, no
  navigation needed).
  Reverse direction also reproduces: turning Cloud rewriting OFF while the
  Rewrite screen is alive but not focused, then returning to it directly,
  also shows a stale "Cloud"/ready pill until an unrelated RewriteController
  state change occurs.
Reproducibility:  Always (3/3 attempts, both directions), but requires the
  Rewrite screen to have been built at least once already in the current
  app session — a completely fresh process reads the correct state on
  first render (no staleness possible, since there's nothing stale to
  show yet).
Impact/scope: This is a **display-only** staleness bug, not an enforcement
  gap. `RewriteController.routing` (state/rewrite_controller.dart:98) is a
  plain getter that calls `TargetRouter.route()` fresh on every access —
  it is not cached. Actually tapping "Rewrite" while the pill is stale
  still runs against the real, current policy (confirmed separately while
  investigating NETLOG-MISSING-CLOUD-BLOCK-001 today: tapping Rewrite with
  the policy genuinely off produces the correct block + snackbar every
  time, regardless of what the pill was showing beforehand). So no request
  is ever incorrectly allowed or blocked because of this — only the
  glanceable status indicator lies until the user interacts with something
  else on the screen.
Screenshot/video: testing/mobile/screenshots/47_pill_stale_not_ready_after_reenable_20260813.png
                   (pill + banner both stale, toggle confirmed ON moments earlier)
                   testing/mobile/screenshots/48_pill_corrected_after_typing_20260813.png
                   (same screen, immediately after typing "a" — pill now "Cloud", banner gone)
Suspected cause:  `ProcessingIndicator.build()` (lib/widgets/processing_indicator.dart:21)
                   does `context.watch<RewriteController>().routing` — it only
                   rebuilds when `RewriteController` itself calls
                   `notifyListeners()`. `NetworkPolicy` (a separate
                   `ChangeNotifier`, services/network/network_policy.dart:13)
                   notifies its own listeners when a Privacy toggle changes,
                   but nothing wires `RewriteController` to also notify when
                   `NetworkPolicy` changes — so the already-built
                   `ProcessingIndicator` (and whatever renders the "Cloud
                   rewriting is turned off" banner, likely the same
                   `routing`/`RoutingDecision` read) simply never rebuilds
                   until an unrelated `RewriteController` mutation (text
                   change, tone/intensity/audience change, mode toggle, a
                   rewrite attempt) happens to trigger one. Likely fix:
                   have `RewriteController` subscribe to `NetworkPolicy` (and
                   forward its notifications) or have `ProcessingIndicator`
                   watch both `RewriteController` and `NetworkPolicy`.

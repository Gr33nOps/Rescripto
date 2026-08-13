ID:               AUTHORING-LIST-REFRESH-001
Severity:         Medium
Area:             Settings > Tones, Settings > Audiences (and, by the same
                   code shape, the Network log's pull-to-refresh)
Feature:          Refreshing the "hidden built-ins" section after
                   returning from the Tone/Audience editor
Device/API:       Rescripto_Test, Android 15 (API 35), x86_64 emulator
App build/commit: debug APK built from HEAD `2365240`
                   ("Bump version to 1.1.1 for release") during this QA
                   pass
Preconditions:    None.
Steps to reproduce:
  1. Settings > Tones (or Audiences).
  2. Tap any tone/audience to open its editor.
  3. Navigate back (hardware/gesture back, or the AppBar back arrow) to
     return to the list.
Expected behavior:
  Returns to the list cleanly; if a hidden built-in was restored while in
  the editor, the "Hidden" section reflects it. No exception, logged or
  otherwise.
Actual behavior:
  An uncaught exception is thrown and logged every single time you return
  from the editor, whether or not anything was actually changed:
    setState() callback argument returned a Future.
    The setState() method on _AudienceListScreenState#... was called with a
    closure or method that returned a Future.
  It does not crash the screen or show a red error screen — it's thrown
  from a non-build async callback, so Flutter's default zone error handler
  just logs it and swallows it. Visually nothing looks wrong, which is
  exactly why this is easy to miss without reading logcat. But because the
  exception is thrown from inside setState()'s own `assert()`,
  `_element!.markNeedsBuild()` (the line after that assert) never runs —
  so the fix's actual intent, "show the newly-restored hidden tone/audience
  without requiring an unrelated rebuild," silently fails too.
Reproducibility: Always — reproduced live via Appium on Settings > Tones
  (opening "Professional"), Settings > Audiences (opening "coworkers"), AND
  Privacy & network > Network log (pull-to-refresh gesture — same
  exception, logged separately at
  `testing/mobile/logs/logcat_20260812_203628.txt:812`, confirming the
  `network_log_screen.dart:39` instance is real and not just theoretical).
  Also reproduced deterministically under `flutter test` (see below).
Screenshot/video: No visual artifact — nothing changes on screen; see
  `testing/mobile/logs/logcat_20260812_170726.txt:720-729` for the two
  live captures (one from returning out of the Tone editor's crash screen
  back to the Tones list, one from returning out of the Audience editor
  back to the Audiences list).
Relevant logs:    testing/mobile/logs/logcat_20260812_170726.txt, lines
                   720 and 729 (`Unhandled Exception: setState() callback
                   argument returned a Future.`)
Suspected cause:  Both `lib/screens/authoring/tone_list_screen.dart:27-29`
                   and `lib/screens/authoring/audience_list_screen.dart:26-28`
                   have the identical `_refreshHidden()`:
                       void _refreshHidden() {
                         setState(() => _hidden = context.read<ConfigStore>().hiddenAudiences());
                       }
                   The closure's body is an *assignment expression*
                   (`_hidden = future`), and in Dart an assignment
                   expression evaluates to the assigned value — so the
                   closure, when called as a `VoidCallback`, actually
                   returns the `Future<List<...>>` that `hiddenAudiences()`
                   (or `hiddenTones()`) produced. `State.setState()`
                   explicitly checks for and rejects this
                   (`framework.dart`'s `setState()` throws
                   `FlutterError('setState() callback argument returned a
                   Future.')` when its callback's return value `is
                   Future`). `_refreshHidden()` is called from
                   `_openEditor()` right after `await
                   Navigator.of(context).push(...)` resolves — i.e. every
                   time the editor is closed, by any means. The identical
                   assignment-expression shape also exists in
                   `lib/screens/network_log_screen.dart:39`
                   (`setState(() => _entries = future);`, inside
                   `_refresh()`, wired to `RefreshIndicator.onRefresh`) —
                   confirmed live: pulling to refresh on the Network log
                   screen throws the identical exception every time.
                   Fix shape: split into two statements —
                   `final next = context.read<ConfigStore>().hiddenAudiences(); setState(() => _hidden = next);`
                   — so the closure's body is only the assignment
                   statement (which returns `void`), not an expression
                   whose value escapes.
                   Note this is checked inside `setState()`'s own
                   `assert()`, so — unlike PROVIDER-001 — this specific
                   throw is compiled out in release builds; the assignment
                   itself still happens either way. But `markNeedsBuild()`
                   being skipped only happens *because* the assert throws,
                   so in release (no assert) the rebuild presumably *does*
                   happen and the visible bug may be debug-only. Not
                   verified against a release build in this pass.

Regression test added: `test/audience_list_screen_test.dart` — pumps a
real `AudienceListScreen` backed by a real (temp sqlite) `ConfigStore`,
opens the first audience, navigates back, and asserts
`tester.takeException()` is null. Currently **failing**, reproducing the
exact production stack trace
(`_AudienceListScreenState._refreshHidden` →
`_AudienceListScreenState._openEditor`) — run `flutter test
test/audience_list_screen_test.dart` to reproduce. Not duplicated for
`tone_list_screen.dart` since it's the identical bug in the identical
shape; the test's doc comment notes this. No production code was changed
to make this test pass, per the "don't change application behavior to make
a test pass" rule.

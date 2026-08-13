# Rescripto mobile QA environment

Automated Android testing setup: **Claude Code → Appium MCP → Android Emulator → Rescripto**.

This lets Claude drive the real app like a person would — launch it, tap
buttons, type text, scroll, navigate, take screenshots, inspect the UI
hierarchy, and read logs — without any test-only code paths in the app
itself.

## Why x86_64, and the arm64-only native libs

Rescripto's native LLM/Whisper stack (`third_party/flutter_llama`,
`third_party/flutter_whisper`) is built **arm64-v8a only** — see
`android/app/build.gradle.kts`'s `ndk { abiFilters += listOf("arm64-v8a") }`.
The natural instinct is to test on a matching arm64-v8a emulator. That was
tried first here and doesn't work on this machine:

```
FATAL | Avd's CPU Architecture 'arm64' is not supported by the QEMU2
        emulator on x86_64 host. System image must match the host
        architecture.
```

Current Android Emulator releases (this one: 37.1.11.0) have dropped
cross-ISA QEMU emulation entirely — an arm64 *system image* cannot boot on
an x86_64 host at all anymore, full stop, regardless of CPU vendor. (This is
different from ARM *app* translation, a separate, narrower feature for
running arm-only app code inside an x86_64 *system image* — see below.)

So `Rescripto_Test` runs `google_apis` **x86_64**, Android 15 (API 35),
Pixel 7 profile, WHPX-accelerated. Empirically on this AMD Ryzen host: the
arm64-v8a-only debug APK **does install and launch successfully** on this
x86_64 image — Android's ABI matching didn't block it, and the app reached
the main UI with no native-load crash. That's more permissive than expected
going in (the assumption was this needed an Intel host's ARM-translation
feature, which wouldn't exist on AMD). What is **not** yet verified is
whether an actual **Local-mode rewrite** (which dlopen's `libllama.so`)
succeeds — a UI smoke test doesn't exercise that path. Treat local on-device
generation as unverified until a QA pass actually runs one; if it fails with
an `UnsatisfiedLinkError`/`dlopen failed`, that confirms the native library
genuinely can't run here and Local-mode tests should be marked Blocked on
this specific machine, not Failed (Cloud/Hybrid and everything else are
unaffected).

If this setup ever moves to real arm64 hardware or an arm64 host (e.g.
Apple Silicon, or a physical Android phone), that would be the way to get
guaranteed-correct native-code coverage.

## One-time setup already done

- Android SDK: `D:\Android\Sdk` (cmdline-tools, platform-tools, build-tools
  36.0.0, emulator binary, NDK).
- System image: `system-images;android-35;google_apis;arm64-v8a` (Android 15).
- AVD `Rescripto_Test` created from that image (see `start_test_device.ps1`
  if it ever needs recreating — the exact `avdmanager create avd` command is
  in this repo's setup history / the final setup report).
- Appium MCP registered with Claude Code: `claude mcp list` should show
  `appium-mcp` as connected. It runs via `npx -y appium-mcp@latest` with
  `ANDROID_HOME`/`ANDROID_SDK_ROOT`/`JAVA_HOME` set in its env.
- Flutter's Android project already declares the app package
  (`com.rescripto.rescripto`) and its `.MainActivity`, plus the
  `PROCESS_TEXT`, `SEND` (share target), and Quick Settings tile
  (`RescriptoTileService`) integrations under test.
- Key interactive widgets across `lib/screens/**` and `lib/widgets/**` carry
  stable `Semantics(identifier: '...')` values (see the setup report for the
  full list) so UiAutomator2/Appium can find them reliably instead of
  relying on visible text alone.

## Everyday workflow

```powershell
# 1. Boot the dedicated emulator (idempotent — safe if already running)
testing\mobile\start_test_device.ps1

# 2. Build the latest debug APK and install/launch it
testing\mobile\build_and_install.ps1

# 3. Drive the app via Appium MCP tools from Claude (see MOBILE_TEST_PLAN.md)

# 4. Pull logs for anything suspicious
testing\mobile\collect_logs.ps1            # point-in-time dump
testing\mobile\collect_logs.ps1 -Follow    # live tail

# 5. Reset to a clean-install state between test passes
testing\mobile\reset_app.ps1 -Relaunch
```

`capabilities.json` in this folder is the Appium session config (package,
activity, AVD name, timeouts) — pass it to whatever WebDriver/Appium-MCP
session-creation call is used.

## Directory layout

```
testing/mobile/
  README.md              This file.
  MOBILE_TEST_PLAN.md     What to test and how, for any future Claude session.
  capabilities.json       Appium session capabilities for Rescripto_Test.
  start_test_device.ps1   Boot + wait for full boot.
  build_and_install.ps1   flutter build apk --debug, install, launch.
  collect_logs.ps1        Filtered logcat dump/tail.
  reset_app.ps1           Force-stop + clear app data.
  reports/                Bug reports from QA passes (tracked; contents gitignored per-run — write dated .md files).
  screenshots/            Screenshots captured during QA (gitignored).
  recordings/             Screen recordings (gitignored).
  logs/                   logcat dumps (gitignored).
```

Only the scripts, docs, and this structure are tracked in git — the actual
run output (screenshots, recordings, logs) is gitignored since it's large
and regenerated every run. If a bug report is worth keeping, put the
markdown report itself under `reports/` — see `.gitignore` for the exact
carve-out (`.gitkeep` placeholders keep the empty dirs, everything else in
them is ignored).

## Known pre-existing issues (not introduced by this setup)

- `test/backup_service_test.dart`: *"BackupService.restore a full
  export-then-restore round trip through encryption merges cleanly"* times
  out after 30s on this machine (Argon2id key derivation is CPU-heavy; 362
  of 363 unit tests pass). Not touched — see the "don't modify production
  code to hide failures" rule in the setup report.

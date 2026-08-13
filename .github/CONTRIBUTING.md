# Contributing to Rescripto

Thanks for taking the time to contribute. This document covers the local
dev workflow, what CI checks, and what makes a PR easy to review.

## Before you start

- For anything beyond a small fix, open an issue first to talk through the
  approach — it saves rework on both sides.
- Read the [README](../README.md), especially
  [Architecture](../README.md#architecture) and
  [Processing modes](../README.md#processing-modes), before touching
  routing, network policy, or the engine abstractions. Those areas have
  non-obvious invariants that are easy to quietly break.
- Security issues go through [SECURITY.md](SECURITY.md), not a public issue
  or PR.

## Local setup

See [Development setup](../README.md#development-setup) in the README for
toolchain prerequisites. Once installed:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The two vendored packages under `third_party/` are excluded from root
analysis and need their own check:

```sh
cd third_party/flutter_llama && flutter analyze lib && flutter test
cd ../flutter_whisper && flutter analyze lib && flutter test
```

All four of the commands above are exactly what CI runs on every push and
pull request (`.github/workflows/ci.yml`) — if they're clean locally, CI
should be too.

## Making a change

- Keep PRs focused. A bug fix doesn't need a drive-by refactor; a new
  screen doesn't need to also reorganize an unrelated module.
- Match the existing code's style: doc comments explain *why* a piece of
  code is shaped the way it is (a constraint, a past bug, a trade-off), not
  *what* it does line by line. Prefer that same tone in commit messages and
  PR descriptions.
- If you find and fix a deterministic bug, add a regression test alongside
  the existing ones in `test/` following that file's own style — see
  `test/rewrite_controller_test.dart` or `test/config_store_test.dart` for
  the shape of a good one.
- If your change affects what leaves the device, what a Privacy toggle
  controls, or model/platform support, update the README so it stays
  accurate — the README's own "What leaves the device" table is a promise,
  not just documentation.
- Semantics identifiers (`Semantics(identifier: '...')`) on interactive
  widgets are load-bearing for accessibility and for the project's mobile
  QA tooling — don't remove one without checking what depends on it.

## Testing on a device

`testing/mobile/` has scripts and a QA plan for exercising the app on a
real emulator/device end to end (`MOBILE_TEST_PLAN.md`), beyond what unit
and widget tests cover. Not required for every PR, but worth a look if
you're touching a user-facing flow — Rewrite, onboarding, backup/sync, or
the Android system integrations (`PROCESS_TEXT`, share target, Quick
Settings tile).

## Submitting a pull request

- Rebase or merge `main` before opening, so CI runs against a current tree.
- Describe *why* the change is needed, not just what changed — the "what"
  is visible in the diff.
- Link the issue it closes, if any.
- Expect CI (analyze, test, both vendored packages, an Android debug
  build) to pass before review. A maintainer will look once it's green.

## License of contributions

By submitting a contribution, you agree it's licensed under this project's
[Apache License 2.0](../LICENSE) (the same terms as the rest of the
non-`third_party/` source), unless you state otherwise in the PR.

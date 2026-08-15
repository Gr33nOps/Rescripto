# Contributing to Rescripto

Thanks for being here. This guide explains how to get the app running, what
the checks cover, and how to make a pull request easy to review.

## Before you start

- For anything larger than a small fix, please open an issue first. A quick
  conversation early on often saves everyone time later.
- Read the [README](../README.md), especially
  [Architecture](../README.md#architecture) and
  [How processing works](../README.md#how-processing-works), before touching
  routing, network policy, or the engine abstractions. Those areas have
  non-obvious invariants that are easy to quietly break.
- Security issues go through [SECURITY.md](SECURITY.md), not a public issue
  or PR.

## Local setup

See [Development](../README.md#development) in the README for the required
tools. Once you are set up:

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

These are the same checks CI runs on every push and pull request. If they pass
locally, CI should be straightforward too.

## Making a change

- Keep pull requests focused. A bug fix does not need an unrelated refactor,
  and a new screen does not need a project-wide reorganisation.
- Match the existing code's style: doc comments explain *why* a piece of
  code is shaped the way it is (a constraint, a past bug, a trade-off), not
  *what* it does line by line. Prefer that same tone in commit messages and
  PR descriptions.
- If you find and fix a deterministic bug, add a regression test alongside
  the existing ones in `test/` following that file's own style. See
  `test/rewrite_controller_test.dart` or `test/config_store_test.dart` for
  the shape of a good one.
- If your change affects what leaves the device, a Privacy toggle, or
  model/platform support, update the README too. The privacy table is a
  promise to people who use the app, not just a reference page.
- Semantics identifiers (`Semantics(identifier: '...')`) on interactive
  widgets are load-bearing for accessibility and for the project's mobile
  QA tooling. Don't remove one without checking what depends on it.

## Testing on a device

`testing/mobile/` has scripts and a QA plan for exercising the app on a
  real emulator or device end to end (`MOBILE_TEST_PLAN.md`), beyond what unit
  and widget tests cover. It is not required for every pull request, but it is
  worth using when you touch a user-facing flow: Rewrite, onboarding, backup/sync, or
the Android system integrations (`PROCESS_TEXT`, share target, Quick
Settings tile).

## Submitting a pull request

- Rebase or merge `main` before opening so CI runs against a current tree.
- Describe *why* the change is needed, not only what changed. The diff already
  shows the mechanics.
- Link the issue it closes, if any.
- Please wait for CI to pass before asking for review. A maintainer will take
  a look once it is green.

## License of contributions

By submitting a contribution, you agree it's licensed under this project's
[Apache License 2.0](../LICENSE) (the same terms as the rest of the
non-`third_party/` source), unless you state otherwise in the PR.

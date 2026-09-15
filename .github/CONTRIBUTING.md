# Contributing to Rescripto

Thanks for helping. This guide covers getting the app running, what the
checks do, and how to make a pull request easy to review.

## Before you start

- For anything bigger than a small fix, please open an issue first so we can
  agree on the approach before you spend time on it.
- Read the [README](../README.md), especially
  [Architecture](../README.md#architecture) and
  [How processing works](../README.md#how-processing-works), before touching
  routing, network policy, prompts or the engine code. Those areas have rules
  that are easy to break without noticing.
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

The two native plugins have their own checks:

```sh
cd packages/rescripto_llama && flutter pub get && flutter analyze && flutter test
cd ../../third_party/flutter_whisper && flutter pub get && flutter analyze lib && flutter test
```

CI runs the same checks on every push and pull request, so if they pass
locally, CI should too.

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
- If your change affects what leaves the device, a Privacy switch, or
  model or platform support, update the README too. The privacy table is a
  promise to the people using the app.
- If you change the prompt or a built-in tone, run a few real drafts through
  a local and a cloud model before and after, and bump
  `ConfigSeeder.seedVersion` when a built-in tone's text changes so existing
  installs pick it up.
- Write user-facing text the way you'd say it to someone: short, specific,
  and naming the screen where a problem can be fixed.
- Semantics identifiers (`Semantics(identifier: '...')`) on interactive
  widgets are load-bearing for accessibility and for the project's mobile
  QA tooling. Don't remove one without checking what depends on it.

## Testing on a device

`testing/mobile/` has scripts and a QA plan (`MOBILE_TEST_PLAN.md`) for
testing the app end to end on an emulator or phone. You don't need it for
every pull request, but it's worth running when you change a user-facing flow:
rewriting, onboarding, backup and sync, or the Android integrations (text
selection menu, share target, Quick Settings tile).

## Submitting a pull request

- Rebase or merge `main` before opening so CI runs against a current tree.
- Describe *why* the change is needed, not only what changed. The diff already
  shows the mechanics.
- Link the issue it closes, if any.
- Wait for CI to pass before asking for review.

## License of contributions

By submitting a contribution, you agree it's licensed under this project's
[Apache License 2.0](../LICENSE) (the same terms as the rest of the
non-`third_party/` source), unless you state otherwise in the PR.

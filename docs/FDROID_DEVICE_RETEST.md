# F-Droid device retest

Related review: https://gitlab.com/fdroid/fdroiddata/-/merge_requests/49009#note_4067917436

The isolated QA build was tested on a Redmi 12 (Android 15), leaving the
installed production 1.3.0 app and its data intact. See
[`testing/mobile/reports/2026-10-25_fdroid_language_retest.md`](../testing/mobile/reports/2026-10-25_fdroid_language_retest.md)
for the inputs, complete outputs, model versions, timings, and screenshots.

## Current result

- Gemma 3 1B and Qwen 2.5 1.5B kept the F-Droid reviewer's German sample in
  German, including `13 uhr` and the train cancellation. A German/English
  sample retained its language switches. French, Spanish, and one Chinese
  sample also retained their source languages. This sample set cannot establish
  reliable behavior for every language.
- The exact English meeting draft was checked at Casual / Full and
  Professional / Full. Gemma preserved the observed facts and saved a modest
  rewrite in about 35 seconds. Qwen omitted or changed facts, and the app
  rejected both of its generated rewrites. Professional / Full also produced
  two immediate empty responses until the QA app was restarted.
- Japanese exposed a semantic failure: Gemma changed “I cannot attend the
  meeting” to “the meeting cannot be held” while retaining Japanese script,
  date, time, and number. The current guard cannot detect that meaning change.
  Do not claim that all languages or tones are accurate.
- A silent dictation recording previously appended Whisper's `[ Silence ]`
  marker. The QA build now leaves the draft untouched for a silence-only
  transcript. History, sharing, Quick Settings, custom tones and audiences,
  privacy controls, and a one-step workflow were also exercised. Backup
  export reached Android's share sheet, but restore was not tested on-device.

Production CI and a release-style build pass at `e8331b9`. The full Windows
test suite had one 30-second timeout in an encrypted-backup round trip while
files ran concurrently; that test passed in 3 seconds on its own. Cloud
providers, WebDAV, and the selected-text return flow still lack end-to-end
phone coverage. No 1.3.2 release or F-Droid recipe update has been published.

## Release gate

Before updating the F-Droid recipe, obtain a tested immutable release and
verify reproducibility against its signed APK. Keep the model-specific English
and Japanese limitations visible to reviewers; a saved local result does not
guarantee semantic accuracy. Capture actual phone screenshots for the listing
if the optional screenshot request is addressed.

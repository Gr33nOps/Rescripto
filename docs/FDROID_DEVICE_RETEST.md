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
- Llama 3.2 1B was downloaded and verified as an English-only alternative.
  Professional / Full preserved the facts but was a slight, informal edit;
  Casual / Full omitted the reports and was rejected. It did not improve the
  English tone and fidelity tradeoff in these runs.
- Japanese exposed a semantic failure: Gemma changed “I cannot attend the
  meeting” to “the meeting cannot be held” while retaining Japanese script,
  date, time, and number. The current guard cannot detect that meaning change.
  Do not claim that all languages or tones are accurate.
- A silent dictation recording previously appended Whisper's `[ Silence ]`
  marker. The QA build now leaves the draft untouched for a silence-only
  transcript. A spoken retry captured and inserted both sentences the user
  said, but misheard “Thursday” as “Lutersday.” The draft remained editable.
  History, sharing, Quick Settings, custom tones and audiences, privacy
  controls, and a one-step workflow were also exercised.

At `fc7dbab`, 476 Windows Flutter tests and analysis pass, and an Android
arm64 release-style APK builds. Encrypted backup export/restore, WebDAV
conflict handling, and a mock OpenAI-compatible cloud stream were exercised
on the phone against local endpoints. Real cloud and Nextcloud accounts were
not tested. Android registers Rescripto for selected-text processing, but
this Redmi's selection menu did not expose it, so insertion back into another
app remains unverified. No 1.3.2 release or F-Droid recipe update has been
published.

## Release gate

Local model output is best effort; 100% semantic or tone accuracy is not a
release requirement. Keep the English, Japanese, speech, and selected-text
limitations visible to reviewers and users, and do not claim universal
language support. Before updating the F-Droid recipe, obtain a tested
immutable release and verify reproducibility against its signed APK. Capture
actual phone screenshots for the listing if the optional screenshot request
is addressed.

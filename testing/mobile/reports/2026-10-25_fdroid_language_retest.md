# F-Droid language preservation retest

Device: 23053RN02A (fire_global), Android 15.
Baseline: installed Rescripto 1.3.0, versionCode 19.
User selected Local mode and reported selecting Gemma 3 1B. The test was
started manually because Android denied ADB input injection, even though
USB debugging (Security settings) appeared enabled.

Requested settings: Professional, Moderate, Same length, one variant.
Local mode, Same length and one variant were observed on screen. Tone and
intensity selections were requested from the user, not independently captured.

Input sent through Android ACTION_SEND:

> hallo, ich komm morgen nicht ins buero weil mein zug ausfaellt, bin ab 13 uhr online

Observed output, read directly from the app's UI hierarchy:

> Hallo, I will not be able to come to the office tomorrow because my train has failed. I will be online at 13:00.

Result: reproduced unwanted translation to English and time-format change.
The train cancellation also became a failure. Exact generation duration was
not measured. Screenshot: ../screenshots/rescripto-baseline-result.png.

Updated APK built successfully as a separate application:
com.rescripto.rescripto.qa, label Rescripto QA, version 1.3.1-qa (21).
Built with local Flutter 3.47.2; this is a device-test artifact, not evidence
of reproducibility with the release's pinned Flutter 3.44.9. Signed with the
local Android debug key; signature verification passed.

Installation attempt returned INSTALL_FAILED_USER_RESTRICTED (Install canceled
by user). No existing app data was removed. Updated-model behavior is pending.

## QA app tests on October 26

The user installed `com.rescripto.rescripto.qa` separately and downloaded
Gemma 3 1B. The model appeared Active in the QA app. ADB input control worked
after this installation, so the following settings and outputs were observed
directly: Local mode, Professional tone, Moderate intensity, Same length,
one variant. The exact reviewer draft was sent by ACTION_SEND.

First run with the general language-preservation prompt, starting 00:03:31
PKT and observed finished by 00:05:24 PKT (at most 113 seconds):

> Hallo, I will not be able to come to the office tomorrow because my train has broken down, and I will be online at 13:00.

This reproduces the language and time-format failures. Screenshot:
`../screenshots/rescripto-qa-failed.png`.

Second run with a late, German-language Extra instruction to stay in German
and keep `13 uhr`, starting 00:06:05 and observed finished by 00:07:59 PKT
(at most 114 seconds):

> Hallo, ich komme morgen nicht ins Büro, weil mein Zug ausfällt, und ich bin ab 13 Uhr online.

This keeps the language, train cancellation, numeric hour and German time
form. It still capitalizes `uhr` and remains slow. The instruction has now
been moved into the prompt builder for clearly German drafts; automatic-path
device verification is pending a rebuilt QA APK.

Third run: rebuilt QA APK installed over the same QA package without removing
its data. Extra instructions were empty. The app generated with the automatic
German-language cue, starting 00:10:18 and observed finished by 00:12:13 PKT
(at most 115 seconds). Direct UI output:

> Hallo, ich komme morgen nicht ins Büro, weil mein Zug ausfällt, und ich bin ab 13 Uhr online.

This confirms the automatic cue fixed the language regression for this sample
on the connected phone. It preserves the numeric hour and German time form,
but capitalizes `Uhr`; exact character-for-character preservation remains
imperfect. Screenshot: `../screenshots/rescripto-qa-german-fixed.png`.

The local model consumed roughly 3–4 CPU cores during generation and Android
reported thermal status 0. These observations support that the slow run was
active computation, not a stalled download or thermal shutdown. It is still
much slower than the reviewer's OnePlus result and warrants further performance
work before describing the app as fast on this device.

Mixed-language sample, QA build with no Extra instructions, started 00:13:24
and observed finished by 00:15:10 PKT (at most 106 seconds):

> Hi Maria, ich bin ab 13 uhr online. See you tomorrow.

Output:

> Hi Maria, I am online at 13:00 tomorrow. See you then.

Failure: the German passage was translated, `13 uhr` was reformatted, and
`tomorrow` was moved into the time statement. A second run with an explicit
English/German preservation instruction also translated the German passage:

> Hi Maria, I am online at 13:00. See you tomorrow.

Gemma 3 1B has not been shown to preserve mixed-language text reliably with
this prompt. The app must not claim this case is fixed on the basis of the
German-only result.

## Qwen 2.5 1.5B comparison on October 26

With the user's approval, the QA app downloaded Qwen 2.5 1.5B (1.0 GB shown
in the UI), completed its integrity check and made it Active. Gemma remained
installed. Both comparisons used Local mode, Professional, Moderate, Same
length, one variant and **empty Extra instructions**. The updated build's
automatic German cue was present for the German sample.

The exact reviewer German draft started at 00:25:20 PKT and was observed
finished by 00:27:51 PKT (at most 151 seconds). Output:

> Hello, I will not be in the office tomorrow because my train is delayed. I am available online from 13:00 onwards.

This translates the German, changes a train cancellation to a delay, and
reformats `13 uhr` as `13:00`. Screenshot:
`../screenshots/rescripto-qa-qwen-german-failed.png`.

The mixed-language draft started at 00:28:21 PKT and was observed finished by
00:30:32 PKT (at most 131 seconds). Output:

> Hi Maria, I am available from 13 uhr onwards. We will meet tomorrow.

The German passage becomes English and `See you tomorrow` becomes a meeting
commitment. The time form survives this run. Screenshot:
`../screenshots/rescripto-qa-qwen-mixed-failed.png`.

Qwen is neither a language-fidelity workaround nor a speed workaround for
these samples on this device. The app was actively using CPU during inference.
The updated prompt for an 84-character draft is about 3,655 system-prompt
characters plus 126 fenced-user characters (roughly 1,261 tokens by the app's
UTF-8-bytes/3 estimate, not a tokenizer measurement). This long prefill is a
plausible contributor to the wait, but the current observations do not isolate
it from model and device speed.

The QA APK was rebuilt and reinstalled over the same separate app after adding
an on-device wait explanation and replacing the model catalog's unqualified
speed labels. Its data and both downloaded models remained in place; Gemma was
restored as the active model. The Models screen showed the revised descriptors.
A short rewrite was started only to inspect the progress card, which displayed
"On some phones, an on-device rewrite can take a few minutes." It was then
cancelled. Screenshot: `../screenshots/rescripto-qa-local-wait-hint.png`.

## CPU thread comparison on October 26

The QA app's Performance screen showed the default of 4 CPU threads and a
2,048-token context. With Gemma active, the thread slider was set to 8 and the
same German sample was repeated under Professional, Moderate and Same length.
It started at 00:35:58 PKT and was observed finished by 00:37:17 PKT (at most
79 seconds). Output remained:

> Hallo, ich komme morgen nicht ins Büro, weil mein Zug ausfällt, und ich bin ab 13 Uhr online.

This single run was about 31% faster than the earlier at-most-115-second
default-thread run, though it is not a controlled benchmark and still takes
over a minute. Android reported thermal status 0 after the run. Screenshot:
`../screenshots/rescripto-qa-gemma-8-threads.png`. The QA app's Performance
settings were reset to 4 threads and 2,048 tokens afterwards. The original
Rescripto 1.3.0 app was never changed.

## Shared-language prompt experiment on October 26

At the user's request, the German-only late cue was replaced in a second QA
build (version 1.3.1-qa2, code 22) with one shared, language-neutral check at
the end of the prompt. This build is an experiment, not a verified fix. Gemma
3 1B was active, CPU threads were set to 8, and each case used Professional,
Moderate, Same length, one variant and empty Extra instructions.

Before that replacement, the French draft below was tested on the previous QA
build with 8 threads:

> bonjour, je ne peux pas venir demain parce que mon train est annulé, je serai en ligne à 13 h

It started at 12:13:09 PKT and was observed finished by 12:15:36 (at most 147
seconds). The app returned the French draft with capitalization and punctuation
but appended the unrelated English sentence `Do you need assistance with
something?` Screenshot: `../screenshots/rescripto-qa-french-baseline.png`.

With the shared-language check, the same French input started at 12:20:33 and
was observed finished by 12:22:45 (at most 132 seconds). Output stayed wholly
French and kept `13 h`:

> Bonjour, je ne peux pas venir demain parce que mon train est annulé, je serai en ligne à 13 h.

Screenshot: `../screenshots/rescripto-qa-french-neutral-prompt.png`.

A Spanish draft, `hola, no puedo ir a la oficina mañana porque cancelaron mi
tren, estaré en línea desde las 13 h`, started at 12:23:23 and was observed
finished by 12:26:53 (at most 210 seconds). It stayed in Spanish and kept
`13 h`, but made only a capitalization change:

> Hola, no puedo ir a la oficina mañana porque cancelaron mi tren, estaré en línea desde las 13 h

Screenshot: `../screenshots/rescripto-qa-spanish-neutral-prompt.png`.

Crucially, the exact reviewer German draft started at 12:27:31 and was
observed finished by 12:29:29 (at most 118 seconds). It **regressed** to an
English translation and changed the time format:

> Hallo, I will not be able to come to the office tomorrow because my train has failed. I will be online at 13:00.

Screenshot: `../screenshots/rescripto-qa-german-neutral-prompt-failed.png`.
This shared English reminder cannot replace the German-language cue as a
release fix. A further prompt revision is under test.

The mixed-language draft `Hi Maria, ich bin ab 13 uhr online. See you
tomorrow.` started at 12:30:39 PKT and was observed finished before 12:36.
It collapsed the German clause into English and changed the time format:

> Hi Maria, I am online at 13:00. See you tomorrow.

Screenshot: `../screenshots/rescripto-qa-mixed-neutral-prompt-failed.png`.
This confirms the same prompt cannot reliably preserve code-switching.

A third QA build (1.3.1-qa3, code 23) strengthened the final instruction to
edit clause by clause, preserving verbs and connective words, and to avoid
composing an English paraphrase first. On the same Gemma 3 1B setup, the
reviewer's German input started at about 12:35:00 PKT and was observed
finished by 12:36:58 (at most 118 seconds). It still translated every clause
after the greeting and changed `13 uhr` to `13:00`:

> Hallo, I will not be able to come to the office tomorrow because my train has broken down. I will be online at 13:00.

Screenshot: `../screenshots/rescripto-qa-german-clause-prompt-failed.png`.
The added English instruction alone is not sufficient for this small model.

A fourth QA build (1.3.1-qa4, code 24) moved multilingual edit examples
(Spanish, German, Japanese and Urdu/English) immediately before the draft and
shortened the final language check. The German reviewer input started at
12:41:56 PKT and was observed finished by 12:44:11 (at most 135 seconds).
It still translated the body into English and reformatted the time:

> Hallo, I will not be able to come to the office tomorrow because my train has fallen apart, and I’ll be online at 13:00.

This is a third materially different prompt-only failure with Gemma 3 1B.
The fifth QA build (1.3.1-qa5, code 25) combines a detected-language cue
with a conservative offline result guard. On the same Gemma 3 1B setup, the
reviewer's exact German draft stayed German, preserved `13`, and kept the train
cancellation: `Hallo, ich komme morgen nicht ins Büro, weil mein Zug ausfällt,
bin ab 13 Uhr online.` It started at 12:56:35 PKT and had finished by 12:59.
Screenshot: `../screenshots/rescripto-qa5-german-language-cue-pass.png`.

The mixed German/English sample started at 12:59:42 and had finished by
13:01:50 without a result card or history entry. The guard stopped a bad
result from being presented, but this is **not** a successful rewrite. Its
raw model text was not captured, so the cause is still uncertain. A second
run on qa5 also produced no result; further QA diagnostics are needed.

The French sample started at 13:02:59 and finished after more than two
minutes. It stayed in French: `Bonjour, je ne peux pas venir demain parce que
mon train est annulé, je serai en ligne à 13h.` The model removed the space
in `13 h` but retained the number and unit. Screenshot:
`../screenshots/rescripto-qa5-french-language-cue-pass.png`.

The sixth QA build (1.3.1-qa6, code 26) added a mixed-passage instruction
and stronger script checks for non-Latin text. Its mixed German/English run
also ended without a result at 13:14:14. The phone remained responsive and
was not thermally throttled, but the battery dropped to 29% while charging.
This needs further investigation before any release claim.

The seventh QA build (1.3.1-qa7, code 27) shortened the main prompt from
4,143 to 1,866 system characters for the German test while retaining its
native cue. The mixed sample still translated and reformatted the German
passage: raw model output was `Hi Maria, online starting at 13:00. See you
tomorrow.` The guard blocked it. When the German passage was submitted by
itself, the model returned the correct `Ich bin ab 13 Uhr online.`, but the
guard falsely rejected that short result. That exposed a short-text language
detection error, now addressed by requiring stronger English evidence before
declaring a Latin-script translation.

The eighth QA build (1.3.1-qa8, code 28) added a guarded per-passage fallback.
On the same mixed draft, the first output again collapsed the German clause
into English with `13:00`; a second on-device generation rewrote only the
German passage as `Ich bin ab 13 Uhr online.` The app assembled, displayed and
saved `Hi Maria, ich bin ab 13 Uhr online. See you tomorrow.` History was
checked. Screenshot: `../screenshots/rescripto-qa8-mixed-passage-pass.png`.
The compact main prompt still regressed the full German reviewer draft,
returning `Hallo, your train will be delayed tomorrow. You will be online at
13:00.` The guard blocked it. The next build restores the prior long prompt
and retains the passage fallback.

The ninth QA build (1.3.1-qa9, code 29) restored the long main prompt while
retaining the passage fallback and a native-language retry for a rejected
single-language result. Gemma 3 1B returned the correct German reviewer
rewrite again at 13:39 and saved it to history:
`Hallo, ich komme morgen nicht ins Büro, weil mein Zug ausfällt, bin ab 13 Uhr
online.` Screenshot: `../screenshots/rescripto-qa9-german-pass.png`.

The same mixed draft was tested on qa9. The first output translated its
German clause and changed `13 uhr` to `13:00`; the fallback rewrote that
clause as `Ich bin ab 13 Uhr online.` The final displayed and saved output was
`Hi Maria, ich bin ab 13 Uhr online. See you tomorrow.` Screenshot:
`../screenshots/rescripto-qa9-mixed-pass.png`.

The Spanish draft on qa9 returned unchanged initially, so the existing
unchanged-output retry ran. The final result stayed Spanish and kept `13 h`:
`Hola, no puedo ir a la oficina mañana porque cancelaron mi tren, estaré en
línea desde las 13 h`. The main change was capitalization; the source was
already otherwise grammatical. Screenshot:
`../screenshots/rescripto-qa9-spanish-pass.png`.

This is sample-based phone evidence, not a guarantee for every language or
every model. Qwen's earlier German and mixed failures are documented above;
the new fallback has not yet been checked with Qwen. Flutter 3.44.9 (the
release/F-Droid pin) resolved `pubspec.lock` with `--enforce-lockfile` and
passed static analysis on these changes.

On qa9, an English draft about moving a Tuesday 3pm meeting to Thursday
10am and bringing 12 reports from Maria remained English and retained the
question, days, times, name and number. The edit only added punctuation
after `Hey`; screenshot: `../screenshots/rescripto-qa9-english-pass.png`.

A short Japanese draft, `明日は休みです 会議は金曜日です`, was returned unchanged after the
app's retry. It did not switch scripts, but it did not improve punctuation
either, so Japanese editing quality remains unverified on this model.
Screenshot: `../screenshots/rescripto-qa9-japanese-unchanged.png`.

The pinned Flutter 3.44.9 SDK passed 462 application tests and static
analysis. A clean Windows QA APK build with that SDK failed when Gradle's JVM
ran out of native memory; a second build with a smaller Gradle heap failed
the same way. The earlier qa9 APK was built on this machine with Flutter
3.47.2 and temporary local diagnostic logging enabled. The diagnostic code
was removed from the source after the build. A fresh clean APK still needs
to be produced before distributing it.

## Clean Linux QA builds and extended phone pass (October 26–27)

An isolated `com.rescripto.rescripto.qa` APK was built from the same Linux
release workflow as production, signed locally with the Android debug key,
and upgraded over the earlier QA app without touching the installed
`com.rescripto.rescripto` 1.3.0 app. The QA package retained both downloaded
models after upgrades. QA30 (code 302) and QA31 (code 312) ran on a Redmi 12
with Android 15.

Qwen 2.5 1.5B on QA30 preserved the F-Droid review's German sample as German,
with `13 Uhr` intact. It also preserved the German and English clauses in
`Hi Maria, ich bin ab 13 uhr online. See you tomorrow.` The resulting mixed
text was `Hi Maria, ich bin ab 13 Uhr online. See you tomorrow.` The edit was
minor but did not translate. QA30 Gemma and Qwen English attempts retained
all days, times, names and numbers but made little more than punctuation
changes, even when Full rewrite was explicitly selected. QA31's stronger
long prompt did not fix Qwen Full: its result was `Hey sorry, I cannot make
the meeting on Tuesday at 3pm. Can we move it to Thursday at 10am? I will
bring the 12 reports from Maria.` This is not a satisfactory Full rewrite.
The QA31 Gemma Full attempt ended without a saved result. The precise cause
was not visible in the release build; treat it as a failed case.

On QA31, History search, detail, copy, paste and share were exercised; the
correct rewritten text appeared in the Android share sheet. Simple/Pro,
model switching, light/dark appearance, custom-tone and custom-audience
create/edit/delete, and privacy controls worked in the observed UI. The
cloud-disabled banner linked to Privacy, and the network kill switch disabled
network controls. Cloud rewriting was left disabled and no paid provider was
used. A one-step local workflow completed on the phone and displayed/saved
`Please send the report tomorrow.` from `please send the report tomorrow`,
but took several minutes and only capitalized the first word. This is a
functional pass with a clear quality/performance limitation.

In the custom-tone editor, the four-digit `1024` output-token value wrapped
at the phone's large text scale. A 72-pixel, single-line value slot is in
QA32 (code 322), built and installed; visual verification is pending phone
unlock. QA33, containing a separate Astra-written compact English prompt and
Sol-wired routing for confidently English local drafts, is building. The
multilingual prompt and result guard remain in place for non-English and
mixed drafts. The first QA33 English Full run, with Qwen 2.5 1.5B, completed
in roughly one minute. It produced `I apologize, I cannot attend the meeting
on Tuesday at 3pm. Can we reschedule to Thursday at 10am instead? I will
bring the 12 reports from Maria.` This is a materially stronger edit than
QA31's near-copy and retains the facts. A matching Gemma 3 1B Full run also
finished within roughly a minute but had no saved result. The cause remains
unknown in this release-style build. One Qwen success does not establish
universal English reliability or all-language quality.

QA33 Qwen Professional Moderate rewrote a Chinese sample while retaining
Chinese script, the question, and `3`/`12`: `我明天不能参加会议，可以改到周五下午3点吗？我会带12份报告。`
became `明天不能参加会议，可以改到周五下午3点吗？我会带来12份报告。`
It took about three minutes and the edit was modest. A Japanese Full run
with `明日の会議に行けません。金曜日の午後3時に変更できますか？資料は12部持っていきます。`
ended without a saved result after roughly four minutes. On QA34 the
Japanese Moderate run eventually appeared in History unchanged at 01:50;
it had run for roughly six minutes and was being stopped at about the same
time, so this is not a useful quality pass. The diagnostic QA35 build is
intended to show why this sample takes so long.
The same English meeting draft in Qwen Casual/Full (Same length) finished
in about a minute but produced no saved result. The Professional/Full
success therefore does not generalize to every tone.

QA34 (code 342) also fixes the routing-status header. Before this build a
cold start could show `Setup needed` / `Local: no model installed` while
Models showed an installed active model. After QA34 installation and after a
force-stop/relaunch, the header correctly showed `Local` immediately.

## QA35–37 follow-up (October 27)

QA35 captured the raw Qwen 2.5 1.5B output for the Japanese Professional /
Moderate meeting draft. It retained Japanese script, Friday at 3, and 12
copies, but changed the polite `変更できますか？` to the blunter `変更できるか？`.
The phone eventually returned to Rewrite; the unchanged-output retry added
in QA36 therefore was not exercised by this case.

QA36 (code 362) upgraded over QA35 without losing either downloaded model.
On the English meeting draft, Qwen Casual / Full saved `I am unable to attend
the meeting on Tuesday at 3pm. Could we reschedule it to Thursday at 10am? I
will provide Maria's 12 reports.` It changed wording, retained the days,
times and 12, but sounded formal and changed the relationship in `reports
from Maria`. Gemma Casual / Full also saved a formal rewrite: `I cannot attend
the meeting on Tuesday at 3pm. Would it be possible to reschedule it to
Thursday at 10am? I will deliver the 12 reports from Maria.` The new Astra
English prompt for QA37 explicitly distinguishes rewriting strength from
formality and names source/destination relationships. Its phone outcome is
pending.

Gemma Professional / Moderate on the Japanese sample returned in 124,631 ms:
`明日の会議は行えません。金曜日の午後3時に変更できますか？資料は12部持っていきます。`
This **fails semantic fidelity**: the source says the speaker cannot attend,
while the result says the meeting cannot be held. The present guard checks
language/script/numeric drift but cannot prove that all semantic roles are
preserved. Do not treat a saved multilingual result as guaranteed accurate.
The screenshot is `../screenshots/rescripto-qa36-gemma-japanese-semantic-fail.png`.

The pinned Flutter 3.44.9 suite passed 473 tests; static analysis was clean.
The focused 40 prompt-builder tests passed after Astra's English prompt edit.
The QA Quick Settings tile was added through Android's status bar service,
then clicked after copying a result. It opened the rewrite screen with the
copied text in the input field. The temporary QA tile was removed afterward.

Voice dictation asked for microphone access only after the mic was tapped. A
one-time 141 MB local speech-model download completed, after which recording
began. Transcribing the test's unspoken recording took tens of seconds and
appended the literal `[ Silence ] [ Silence ]` to the existing input. A narrow
fix now treats silence-marker-only local transcripts as empty; its unit test
and analyzer pass, but a new on-device build is still needed to confirm it.

QA37 (code 372) tested the first Astra English tone revision against the
reviewer's exact meeting draft in Casual / Full. Gemma returned `Hey, sorry
about the meeting on Tuesday at 3pm. Can we reschedule it to Thursday at
10am? I’ll bring the reports from Maria.` after 48,297 ms; it omitted `12`,
so the app rejected it and saved nothing. Qwen returned `Can we reschedule the
meeting to Thursday at 10am? I'll bring Maria's 12 reports.` after 60,258
ms; it omitted the speaker's inability to attend and Tuesday at 3pm, and
changed the relationship to Maria. The app rejected that too. This revision
is not an English quality pass. Astra's next revision makes information
preservation the primary instruction and asks for each clause in order;
QA39 will test it on the phone.

QA38 used the same APK version code but included the silence-transcript fix.
After the one-time microphone permission and model initialization, a short
silent recording completed transcription and left the empty input unchanged.
This confirms the observed `[ Silence ]` regression is fixed on device.

The QA Backup screen accepted matching test passphrases with sensitive-data
toggles left off. Export created a `.rescriptobackup` file and opened Android's
share sheet. No external share destination was selected, so restore and the
encrypted file's round-trip contents remain unverified on the phone.

QA40 (code 402) used Astra's fact-first English prompt. On the exact reviewer
draft with Casual / Full, Qwen returned `Sure, could we reschedule the meeting
to Thursday at 10am instead? I'll bring Maria's 12 reports then.` after
45,024 ms. It omitted the inability to attend and Tuesday at 3pm and altered
the `from Maria` relationship, so the app correctly rejected it. Gemma
returned `Sorry, I cannot make the meeting on Tuesday at 3pm. Could we move it
to Thursday at 10am? I will bring the 12 reports from Maria.` after 34,915
ms. This retained all observed facts and saved successfully, but was only a
modest Full rewrite. Screenshot:
`../screenshots/rescripto-qa40-gemma-english-casual-full.png`.

Qwen Professional / Full on that same draft first produced two immediate
empty responses in a still-running app. After a QA-app force stop and restart,
it returned `Sure, I can make the meeting on Thursday at 10am instead. Could
you bring those 12 reports from Maria?` in 43,698 ms. This inverted the
speaker's availability and who would bring the reports and omitted Tuesday
at 3pm. The app rejected the result and saved nothing. This is a clear
counterexample to treating a Full rewrite from Qwen as reliable English QA.

Gemma Professional / Full on the same source returned `Sorry, I cannot make
the meeting on Tuesday at 3pm. Could we move it to Thursday at 10am? I will
bring the 12 reports from Maria.` in 34,488 ms. It saved and retained the
observed facts, but matched Gemma's Casual / Full output word for word. The
tone setting therefore did not produce a meaningful difference in this test.

The full Windows Flutter suite reached 473 passing tests and one 30-second
timeout in the encrypted-backup round-trip test while test files were running
concurrently. That exact test passed in 3 seconds when rerun alone. The
production branch's Linux CI and release-style build both passed at
`e8331b9`; no production release or F-Droid recipe update has been made.

Llama 3.2 1B (English, Q4_K_M, 770 MB) was downloaded over Wi-Fi and passed
the app's file verification. On the exact reviewer English draft,
Professional / Full returned `I won't be able to make the meeting on Tuesday
at 3pm, could we move it to Thursday 10am? I will bring the 12 reports from
Maria` in 34,843 ms. The app saved it, and the observed facts remained, but
the edit was slight and still informal. Casual / Full returned `I won't be
able to make the meeting on Tuesday at 3pm. Would it be possible to move it
to Thursday 10am?` in 34,341 ms, omitting the reports, count, and Maria; the
app rejected it. Llama is therefore not a demonstrated stronger English
fallback on this phone. Gemma was restored as the active QA model afterward.

CI on the documentation commit `8e74ffe` passed as well. The versioned app
code and release-style build remain at `e8331b9`.

## October 27 release-gate continuation

On Redmi 12, Llama 3.2 3B Q4_K_M (1.9 GB) passed its model-file
verification. The exact reviewer English draft in Professional / Full
returned after 111,856 ms: `Can we reschedule the meeting from Tuesday at
3pm to Thursday at 10am? I will bring the 12 reports from Maria.` The app
saved it, but it omitted the speaker's explicit inability to attend. Casual
/ Full took 121,112 ms and returned `Hey, I won't be able to make the meeting
on Tuesday at 3pm. Can we move it to Thursday at 10am? I will bring the
reports from Maria that are due today.` It dropped `12` and invented `due
today`; the app rejected it with `RewriteFidelityException`. The 3B model is
neither a fast nor a dependable English default on this reference phone.

An encrypted backup exported through Android's share sheet to Download as
`rescripto-backup-20261027-1349.rescriptobackup`. The QA app picked that file,
decrypted it using the test passphrase, and previewed 14 tones, 6 audiences,
1 workflow, 0 cloud providers, and 0 history items. Settings-only restore was
confirmed and returned to the Backup screen; the other content sections were
left unchecked. This covers an actual exported-file round trip, though it
does not prove a cross-device restore.

With explicit QA-app Backup sync permission and a local WebDAV test endpoint,
the app's connection test returned `Connected successfully.` Sync sent
`PROPFIND`, `PUT`, then `PROPFIND`; the server stored a 6,763-byte encrypted
backup and the app showed a `Last synced` timestamp. After the server copy
was advanced, the app warned `The server copy has changed`, offered review
and overwrite choices, and downloaded (`GET`) then applied the server's copy
only after confirmation. This proves protocol and conflict behavior against
the local endpoint, not compatibility with a real Nextcloud account.

With explicit QA-app Cloud rewriting permission, the custom
OpenAI-compatible endpoint connection test returned `Connected successfully.`
The phone sent `POST /v1/chat/completions` to the local streaming test server
and displayed its fixed output, `Hello, I can send the report tomorrow.` The
QA app was returned to Local mode with Gemma 3 1B active. This does not test
a paid cloud provider or measure its rewrite quality.

The first intentional voice test produced an empty draft. The user confirmed
they missed the recording window, so it is inconclusive and requires a retry.
Selected-text return remains unverified end to end. The production app on the
phone remains v1.3.0; tests used the separate v1.3.2 QA package.

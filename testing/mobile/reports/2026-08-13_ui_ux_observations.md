UI/UX OBSERVATIONS  -  2026-08-13 mobile QA pass
Device/API:       Rescripto_Test, Android 15 (API 35), x86_64 emulator
App build/commit: debug APK built from HEAD `2365240`, PROVIDER-001 fix applied

These are visual/interaction-design observations, not correctness bugs  -  the
app already renders consistently and matches Material Design conventions
throughout. Filed separately from the functional bug reports since they're
judgment calls about polish, not reproducible defects. Severity here means
"how much friction this adds," not "how broken it is."

---

1. Tone chip row cuts off with no scroll affordance (Low)
   Area: Rewrite screen, Tone selector
   The tone chips (Professional/Casual/Friendly/Formal/...) sit in a
   horizontally-scrolling row, but the row is exactly tall/wide enough that
   the last visible chip is sliced in half at the screen edge
   (see rewrite screen screenshots throughout this pass  -  the 4th "Formal"
   chip's icon is always partially cut off). Nothing hints the row scrolls:
   no fade-out gradient at the edge, no partial-next-item peek, no arrow.
   A user who doesn't habitually swipe UI rows sideways may never discover
   there are more tones than the ~3.5 visible. Fix shape: end the visible
   row a few px earlier so the last chip is either fully shown or clearly
   half-cut as an intentional "there's more" affordance, or add a fade
   mask on the trailing edge.

2. Dictation button visually dominates the primary text-entry flow (Low/Medium)
   Area: Rewrite screen
   The circular "Tap to dictate" mic button is the single largest, most
   visually weighted element on the whole screen  -  larger than the
   "Rewrite" action button itself, and it sits directly below the text
   field before the user has typed anything. For an app whose primary
   input method is clearly typed/pasted text (the field is labeled "Text
   to rewrite" and shows a live character counter), dedicating that much
   vertical space and visual emphasis to what's presumably a secondary
   input path inverts the expected hierarchy. First-time users may read
   the screen as "a dictation app" before noticing the text field above
   it is the main event.

3. Settings is one long undifferentiated scroll (Medium)
   Area: Settings screen
   Appearance, Processing mode, Editor mode, Authoring (Tones/Audiences/
   Workflows), AI engine (GPU/threads/context sliders), Voice input
   (on-device/cloud + Whisper model size), Privacy & cloud, Backup, and
   About are all stacked in a single continuous `ScrollView`. Reaching
   Backup or About from the top requires 3-4 full-screen swipes past
   sections most users will set once and never revisit (CPU threads,
   context size, Whisper model tier). There's no section jump/anchor nav,
   no sticky section headers, and no visual grouping stronger than a plain
   text label between sections. Worth considering either collapsible
   sections or splitting the more technical AI-engine tuning controls into
   their own sub-screen reachable from a single "Advanced" entry point,
   the way Tones/Audiences/Workflows already got pulled out to their own
   screens.

4. Password validation caption doesn't clear once input becomes valid (Medium)
   Area: Settings > Backup > WebDAV sync > "Set server password" dialog
   After a first save attempt with an effectively-empty field (see
   CLOUD-PROVIDER-STALE-KEY-001's neighbor investigation  -  this shows up
   independent of that), the dialog displays "Use at least 8 characters."
   under the password field. Typing a genuinely valid password afterward
   (19 real characters, confirmed via the masked-dot rendering and a
   successful subsequent Save) did not make this caption go away  -  it
   stayed visible right up until Save was tapped again and succeeded. A
   validation message that doesn't react to the input becoming valid reads
   as the app still rejecting a password the user can plainly see is long
   enough, which is actively confusing rather than just unpolished. Fix
   shape: re-evaluate and clear/hide the helper text on every keystroke,
   not just on submit.

5. "Recommended" badges are low-contrast for how much weight they carry (Low)
   Area: Onboarding (processing-mode cards), Models screen (model list)
   Both onboarding's "Private & Offline" option and the Models screen's
   "Gemma 3 1B" carry a "Recommended" pill that's meant to steer a
   first-time user's choice, but the pill styling (muted grey-on-dark
   background, regular weight text) doesn't stand out much more than the
   surrounding secondary text. For a label whose entire job is to catch
   the eye before the user reads every option in detail, it currently
   reads as just another caption.

6. History entries distinguish original vs. rewritten text by color alone (Low)
   Area: History screen, list entries
   Each history card stacks the original text (dimmer grey) directly above
   the rewritten text (full-white) with no label on either line. The
   contrast is legible, but a user skimming quickly  -  or anyone with
   reduced color/contrast perception  -  has to infer which line is which
   from position and shade alone. An explicit small "Original" / "Rewrite"
   caption (as the Rewrite screen's own result view already uses via its
   Original/Rewrite tab labels) would remove the ambiguity for free.

7. No in-flight indicator for "Sync now" or a Local rewrite while it's running (Low)
   Area: Settings > Backup > WebDAV sync; Rewrite screen in Local mode
   Independent of SNACKBAR-FEEDBACK-MISSING-001 (which covers the
   *end-state* feedback being silently absent on failure): even when
   these actions succeed, there's no visible "working on it" state between
   the tap and the result  -  no disabled button, no spinner, no progress
   text. A slow local model load or a slow WebDAV round trip currently
   looks identical, from the UI, to a tap that did nothing at all, which
   is exactly the ambiguity that made SNACKBAR-FEEDBACK-MISSING-001 so
   easy to mistake for "nothing happened" during this pass. Adding a
   lightweight in-flight state (the button already has the visual language
   for this  -  see the Rewrite screen's AppBar `ProcessingIndicator` used
   during cloud/streaming generation) would help even once the SnackBar
   bug is fixed.

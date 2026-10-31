# Quill: the brief

A menu-bar app that replaces the two MacWhisper features Eric uses. Started 10/30/2026. Name: Eric's pick from Wren, Mynah, Lyre, Quill, Trill, Perch ("a feather you write with: bird into words").

## Who it's for

One user, Eric: Apple Silicon Mac, macOS 15 (Sequoia) at the time of writing, Xcode 26 and Swift 6.2 installed. Often dictates into a terminal or a chat box. Speed from release-of-key to text-on-screen matters more than anything else. Keep it minimal; MVP first, then iterate.

## The two features

1. **Hold to talk → paste at cursor.** A global hotkey (a held modifier: option or right-command, configurable). Start capture on press, stop on release, transcribe, insert at the cursor in whatever app has focus. Must not clobber the clipboard: save it, paste, restore it.
2. **Record → transcribe.** From the menu: record, stop, transcribe; show the text with Copy and Save. Optionally transcribe a dropped audio file.

## Constraints

- Local only. No network at runtime except a one-time model download. No telemetry.
- Menu-bar only (no Dock icon). A small status mark shows idle, listening, transcribing.
- macOS permissions it will need, each asked for by the system and explained in-app: Microphone (capture), Accessibility (the global key and synthesizing the paste).
- Ships as a signed local build Eric can run; no App Store.

## Decisions to make first (walk them with Eric, one at a time, multiple choice)

1. **Language and shape.** Native Swift / SwiftUI `MenuBarExtra` (recommended: the hotkey, paste and permissions are native APIs, and the speech engines below are Swift packages) vs. a Python menu-bar app (`rumps`) on the mlx-whisper / parakeet-mlx stack (faster to prototype, messier permissions and packaging).
2. **The speech engine.** Candidates, to verify against their repos before choosing: Parakeet via FluidAudio (Core ML, very fast English), Whisper via WhisperKit (argmaxinc, broader languages), whisper.cpp. Possibly offer two: a fast default and an accurate one for longer recordings.
3. **The hotkey.** Which key, and hold-to-talk only or also a press-to-toggle mode for long dictation.
4. **Where recordings go.** Kept (a folder, a retention period) or thrown away after transcribing.

## Prior art to read before building (open source, same problem)

Several menu-bar dictation apps already combine these engines; read how they do the hotkey, the paste and the engine switch rather than reinventing it: Hex (dizk/Hex), MacParakeet (moona3k), Ghost Pepper (matthartman), Muesli (forjd), Voicey (jonathanKingston), wispr (sebsto), digimata/quill (a meeting recorder that shares the name). Verify each before relying on it.

## Decisions made

1. **Shape (10/30): native Swift menu-bar app.** SwiftUI `MenuBarExtra`, SwiftPM, no Dock icon, signed with Eric's Developer ID so the Accessibility grant survives rebuilds.
2. **Engine (10/30): FluidAudio Parakeet TDT v2 (English).** Eric's criterion: the most accurate. Parakeet v2's model card reports 6.05% average WER on the Open ASR leaderboard's 8 English sets; Whisper large-v3-turbo is ~7.8% from memory (the leaderboard CSV is login-gated, unverified). It is also the faster one. WhisperKit turbo as a second engine, compared on Eric's own voice, is in IDEAS. FluidAudio v0.18.0 (10/28): every `transcribe` overload takes `decoderState: inout` (the README is stale).
3. **Hotkey (10/30): hold Right Option** (keycode 61), via a CGEventTap. A hold under 0.3 s is discarded; another key or a click in the first 0.5 s cancels (an Option chord). After 0.5 s the hold is committed and only the release ends it (10/30: Hex's cancel-anytime rule threw away a 13.7 s dictation). Hold-to-talk only in v0.1.
4. **Recordings (10/30): never on disk; kept in memory until the paste is confirmed** (Eric: in MacWhisper, "if something grabs the screen focus while I'm transcribing… I lose the audio because it doesn't have anywhere to paste it"). The app frontmost at key-press is the paste target. If another app is frontmost when the text is ready, Quill does not paste: it holds the transcript, marks the icon, and the menu offers Paste / Copy / Re-transcribe. The last clip and text stay in memory until the next dictation pastes. "Confirmed" means Cmd-V went to the same app; macOS cannot confirm that a paste landed, so the menu copy is the backstop.
5. **Warm mic (10/30, Eric: yes).** The mic stays open while Quill runs, with a 0.5 s rolling pre-roll in memory, so a press starts with the audio just before it. Cold starts took 280–720 ms to deliver the first buffer and cut the first words. The cost: macOS's orange mic dot stays on.
6. **The bubble (v0.2, 10/30).** A floating panel just below the text cursor (Accessibility caret bounds; else below the focused field; else by the mouse) shows "Listening → <app>", the live words (the capture re-transcribed every ~0.6 s, a rough draft), then "Writing", or "Held" when focus left the target. The paste is still one full pass on release. Live preview is a menu toggle.

## Next: meeting mode (v0.3, decided 10/30, build next session)

Feature 2 grown into meetings, from the menu. **Menu → Start Meeting**: the icon changes to a record mark, and a small window shows the live transcript (the same rough-draft re-transcription as the bubble). **Stop**: the icon shows transcribing, then a full pass with speaker labels (FluidAudio's `Diarizer` trait, off since v0.1; renameable Speaker 1/2…), opened in a window with Copy and Save.
- **Sources: both, like MacWhisper (Eric).** He records Zoom calls in MacWhisper without picking the Zoom app, and sometimes puts his phone on speakerphone next to the laptop. So: the mic always (it covers in-person and the speakerphone), plus the Mac's audio output when there is any (system audio capture: a Core Audio process tap or ScreenCaptureKit, needing the Screen & System Audio Recording permission). Two tracks, mic and system, also help label who spoke. Check how MacWhisper and the prior art capture system audio before choosing the API.
- **Saving: the Desktop by default (Eric).** Audio and transcript side by side, dated; the folder changeable later. Dictation clips stay memory-only (decision 4).

## Name collision

Other projects are called Quill, including an open-source macOS voice-typing app and digimata/quill. Fine for a personal tool; revisit only if this is ever shared.

## How to work here

- One session builds. Smallest shippable version first: feature 1 alone, one engine, one hotkey, is v0.1.
- Test the real thing: build, run, hold the key in TextEdit and in a terminal, measure release-to-text time.
- Commit as you go; this repo is its own history.

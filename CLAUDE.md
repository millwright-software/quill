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

## Name collision

Other projects are called Quill, including an open-source macOS voice-typing app and digimata/quill. Fine for a personal tool; revisit only if this is ever shared.

## How to work here

- One session builds. Smallest shippable version first: feature 1 alone, one engine, one hotkey, is v0.1.
- Test the real thing: build, run, hold the key in TextEdit and in a terminal, measure release-to-text time.
- Commit as you go; this repo is its own history.

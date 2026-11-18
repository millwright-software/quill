# Changelog

## 0.4.3 (2026-11-18)

- Fixed a crash when opening the menu-bar menu (the menu could rebuild itself while opening until the app ran out of stack). The meeting line in the menu shows the start time instead of a live timer.

## 0.4.2 (2026-11-15)

- The welcome window and Settings say plainly that Quill listens only while the feather is red.
- The mic stays ready for five minutes after you dictate (Settings: Off, 30 seconds, 1 minute, 5 minutes), so back-to-back dictations start instantly; then it closes and the indicator goes off.

## 0.4.1 (2026-11-14)

- The microphone opens only while you hold the key (or while a meeting records), so the mic indicator is off when Quill is idle. The bubble appears once audio is flowing: that's the cue to speak.
- The menu-bar feather turns red while listening.
- A cleaner menu; Option-click shows timings, the log and developer items.

## 0.4.0 (2026-11-14)

- Meetings transcribe with Parakeet by default (seconds, no extra download); Whisper Large v3 Turbo is a choice in Settings.
- Meetings are recorded to CAF files, which stay readable if Quill quits or crashes mid-meeting. The meeting folder holds `mic.caf`, `system.caf`, numbered segments and `meta.json`.
- Recording continues through an audio device change (AirPods connecting, a headset unplugged). System audio restarts into a new numbered segment, and the menu says when a track is recovering or lost.
- A welcome window on first run explains Microphone and Accessibility, checks them, and lets you try dictation.
- README rewritten for new users; Homebrew cask.

## 0.3.1 (2026-11-06)

- Fixed a crash when the audio device changed (AVAudioEngine's tap threw an exception during input changes). The restart now waits and retries until the mic is back.
- Release builds: signed, notarized, published with `scripts/release.sh`; `install.sh` for Macs without Xcode (2026-11-11).

## 0.3 (2026-10-31)

- Feather app icon and menu-bar marks that change with state.
- Settings window (hotkey, live preview, launch at login, permissions) and an About panel.
- Meeting mode: Start/Stop from the menu records microphone and system audio, then transcribes with Whisper Large v3 Turbo into a timestamped `transcript.md` (Me/Them).
- Only the last dictation is kept, in memory. No history, by design.

## 0.2 (2026-10-30)

- Warm microphone with a 0.5 second pre-roll, so the first word isn't clipped.
- The bubble at the cursor shows live words, the target app and held state.
- Live preview toggle.

## 0.1 (2026-10-30)

- Menu-bar app: hold Right Option, speak, release.
- Parakeet TDT v2 transcription on-device.
- Paste at the cursor with the clipboard restored afterward.
- If focus moves to another app, the text is held rather than pasted into the wrong place.

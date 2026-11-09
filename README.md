# Quill

A small macOS menu-bar app for Eric: speak, and the words land as text. Local and private: audio never leaves the Mac.

Two features, the two he actually uses in MacWhisper (Eric, 10/30):

1. **Hold to talk.** Hold a modifier key (option or command), speak, let go: the transcript is pasted wherever the cursor is, in any app.
2. **Record, then transcribe.** Press record, stop, transcribe the recording. Save or copy the text.

Nothing else until those two feel better than MacWhisper.

## Install on a Mac

Needs an Apple Silicon Mac on macOS 15+, and Xcode 26 (Swift 6.2).

```sh
git clone https://github.com/millwright-software/quill.git
cd quill
scripts/build.sh --run      # builds, installs /Applications/Quill.app, launches it
```

The first build fetches the Swift packages (FluidAudio, WhisperKit). Nothing else to install by hand:

- **Dictation model** (Parakeet TDT v2, ~0.5 GB): downloads on first launch, ready in about a minute.
- **Meeting model** (Whisper Large v3 Turbo, ~1.5 GB): downloads the first time you transcribe a meeting; the first load then compiles it for the Neural Engine (10–15 min, once).
- **Permissions**: macOS asks for Microphone, Accessibility, and (on the first meeting) System Audio Recording.

`build.sh` signs with Eric's Developer ID when the Mac has it, otherwise ad-hoc (set `QUILL_SIGN_IDENTITY` to use your own). Ad-hoc builds work, but macOS asks for the permissions again after each rebuild.

Models live in `~/Library/Application Support/` (FluidAudio, Quill/Models). Dictation audio never touches disk; meetings save to `~/Desktop/Quill Meetings/`.

Status: v0.3 in daily use: hold-to-talk dictation with a live bubble at the cursor, and meeting recording with Whisper transcription. See `CLAUDE.md` for the brief and decisions, `IDEAS.md` for the running list.

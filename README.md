<div align="center">
  <img src="Sotto/Assets.xcassets/AppIcon.appiconset/sotto-256.png" width="180" height="180" />
  <h1>Sotto</h1>
  <p>On-device voice-to-text for macOS with AI enhancement — transcribe what you say, almost instantly.</p>

  [![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
  ![Platform](https://img.shields.io/badge/platform-macOS%2026.0%2B-brightgreen)
</div>

---

Sotto is a native macOS app that turns speech into text entirely on your device. Transcription and AI enhancement run locally — nothing you say leaves your Mac.

## Features

- 🎙️ **Local ASR** — transcribe with on-device models (Parakeet via FluidAudio, or Whisper), no network required
- 🔒 **Private by default** — audio and text are processed offline; nothing is uploaded
- ✨ **AI enhancement** — clean up punctuation and formatting on-device with Apple's Foundation Models
- 🫧 **Streaming capsule** — a compact recorder that streams words as you speak and grows with the transcript
- 📝 **Custom vocabulary** — teach the recognizer your names, jargon, and text replacements
- ✅ **Review before paste** — an editable preview of the transcript before it's inserted (⌘↵ to paste, Esc to cancel)
- ⌨️ **Global shortcuts** — configurable hotkeys for push-to-talk and quick recording

## Get Started

### Requirements

- macOS 26.0 or later
- Xcode (to build from source)

### Build from Source

Sotto builds with a single command using the included Makefile:

```shell
make local
```

This builds the app (ad-hoc signed, no Apple Developer account required) and installs it to `/Applications/Sotto.app`. See [BUILDING.md](BUILDING.md) for prerequisites, the manual build path, and how to set up a stable local signing certificate.

## License

Sotto is licensed under the GNU General Public License v3.0 — see the [LICENSE](LICENSE) file for details.

## Relationship to VoiceInk

Sotto began as a fork of [VoiceInk](https://github.com/Beingpax/VoiceInk) by Prakash Joshi Pax (GPL-3.0), taken in July 2026, and has been modified extensively since.

Measured against VoiceInk as of that date, **about 75% of Sotto's app code is new** — 17,325 of 23,118 substantive lines, across 97 files that have no VoiceInk counterpart. The remaining quarter is VoiceInk's work, and Sotto is GPL-3.0 because of it.

**Rewritten or new in Sotto**

| Area | VoiceInk code remaining |
| --- | --- |
| Recorder — capsule, constellation, halo | 3% |
| AI enhancement pipeline | 6% |
| Settings | 7% |
| Shared UI, theme, typography | 8% |

VoiceInk's recorder is `MiniRecorderView` / `NotchRecorderView`. Sotto's is a different surface end to end: a streaming capsule that grows with the transcript, an editable review tray before paste, and a failure HUD with retry.

Also new, with no VoiceInk counterpart: the Gherkin acceptance pipeline (`features/`, `acceptance/`), the unit test suite in `SottoTests/`, on-device enhancement through Apple's Foundation Models, and the adaptive glass material.

**Substantially still VoiceInk**

| Area | VoiceInk code remaining |
| --- | --- |
| Audio device management | 94% |
| Word-agreement streaming engine | 92% |
| Whisper model management | 89% |
| Audio playback UI | 81% |
| Core audio recording | 71% |

## Acknowledgments

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — high-performance inference of OpenAI's Whisper model
- [Silero VAD](https://github.com/snakers4/silero-vad) (MIT) — voice-activity detection weights, fetched at build time
- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Parakeet model implementation
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — user-customizable keyboard shortcuts
- [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin) — launch-at-login support
- [MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter) — media playback control during recording
- [Zip](https://github.com/marmelroy/Zip) — file compression utilities
- [SelectedTextKit](https://github.com/tisfeng/SelectedTextKit) — reading selected text on macOS
- [Swift Atomics](https://github.com/apple/swift-atomics) — low-level atomic operations

<div align="center">
  <img src="Sotto/Assets.xcassets/AppIcon.appiconset/sotto-256.png" width="180" height="180" />
  <h1>Sotto</h1>
  <p>On-device voice-to-text for macOS with AI enhancement — transcribe what you say, almost instantly.</p>

  [![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
  ![Platform](https://img.shields.io/badge/platform-macOS%2014.4%2B-brightgreen)
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

- macOS 14.4 or later
- Xcode (to build from source)

### Build from Source

Sotto builds with a single command using the included Makefile:

```shell
make local
```

This builds the app (ad-hoc signed, no Apple Developer account required) and installs it to `/Applications/Sotto.app`. See [BUILDING.md](BUILDING.md) for prerequisites, the manual build path, and how to set up a stable local signing certificate.

## License

Sotto is licensed under the GNU General Public License v3.0 — see the [LICENSE](LICENSE) file for details.

Sotto is a fork of [VoiceInk](https://github.com/Beingpax/VoiceInk) by Prakash Joshi Pax, licensed under GPL-3.0.

## Acknowledgments

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — high-performance inference of OpenAI's Whisper model
- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Parakeet model implementation
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — user-customizable keyboard shortcuts
- [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin) — launch-at-login support
- [MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter) — media playback control during recording
- [Zip](https://github.com/marmelroy/Zip) — file compression utilities
- [SelectedTextKit](https://github.com/tisfeng/SelectedTextKit) — reading selected text on macOS
- [Swift Atomics](https://github.com/apple/swift-atomics) — low-level atomic operations

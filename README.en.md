# kol-chen · קול-חן

<img src="docs/app-icon.png" width="112" alt="kol-chen dark cassette icon">

**Record what is playing. Keep listening.**

A small native Mac recorder with a dark cassette interface and a little nostalgia.

[עברית](README.md) · [Source](Sources) · [Media notes](docs/media/README.md)

A website plays something you want to keep. Press the red button, keep listening through your usual speakers or headphones, then stop. Your recording stays on your Mac.

<img src="docs/media/app-recording.png" width="680" alt="The running Mac app recording system audio with active stereo meters">

> The app screenshots and video show Popper from my installed version, with specific permission from Ben Natan for demonstrations on my blog and in this public repository’s demo media. The font is not included in this repository; the public build uses system lettering.

## The cassette in motion

This is an actual screen capture of my installed macOS app. The reels turn during recording, stereo meters follow the audio, and the record button becomes a stop square. The clip is silent.

https://github.com/user-attachments/assets/ce37880f-35e6-45d2-be02-e71dcef6f7ad

[MP4](docs/media/app-demo.mp4) · [Animated GIF](docs/media/app-demo.gif)

| Ready | Recording | Saved |
| --- | --- | --- |
| ![Ready](docs/media/app-idle.png) | ![Recording](docs/media/app-recording.png) | ![Saved](docs/media/app-saved.png) |

## Features

- Capture website and application audio as stereo AAC `.m4a` files.
- Keep normal playback without installing a virtual audio device.
- Configure separate global start and stop shortcuts.
- See real stereo meters and recording-driven cassette reels. Respects Reduce Motion.
- Choose a save folder, replay the latest take, and reveal recordings in Finder.
- Continue recording with the window closed using the menu bar controls.

Capture includes all system playback, including sounds from other apps. Protected media may prevent capture.

## Opening a gift

Paper, a tear, a box, and a handwritten dedication: a preview of a more personal welcome.

https://github.com/user-attachments/assets/f7499958-7894-4a36-928b-a376c98be255

**This is a gift-opening design prototype.** It comes from an earlier Windows installer exploration and shows only the unwrapping sequence. It is not connected to a native Mac installer. The current installation path is documented below.

| Wrapped | Opening | Inside |
| --- | --- | --- |
| ![Wrapped parcel](docs/media/gift-wrapped.png) | ![Tearing the paper](docs/media/gift-tearing.png) | ![Revealed box and dedication](docs/media/gift-opened.png) |

[Gift MP4](docs/media/gift-opening-preview.mp4) · [Animated GIF](docs/media/gift-opening-preview.gif)

## Build and run

Requires an Apple Silicon Mac, macOS 15 or later, and Xcode with Swift 6.

```sh
git clone https://github.com/seffyfisher/kol-chen.git
cd kol-chen
zsh build.sh
open build/kol-chen.app
```

The script creates a locally signed app in `build`. You can copy it to Applications. There is currently no notarized DMG or integrated gift installer.

1. Open kol-chen and press the red record button.
2. Allow system audio recording when macOS asks.
3. Play audio on a website or in another app.
4. Press the red stop square to finish and save.

If needed, allow **קול-חן** in **System Settings → Privacy & Security → Screen & System Audio Recording**, then reopen it.

Recordings default to `~/Music/kol-chen`. The gear button opens the save-folder and shortcut settings.

## Your shortcuts

| Action | Default |
| --- | --- |
| Start | Control–Option–Command–R |
| Stop and save | Control–Option–Command–S |

Both combinations are configurable, persist between launches, and work while other apps are active. No Accessibility or Input Monitoring permission is required.

<img src="docs/media/settings.png" width="460" alt="Settings with save-folder selection and configurable start and stop shortcuts">

## Privacy

Recording and processing happen locally. The app does not capture the microphone, upload recordings, or require an account.

## Development

Built with SwiftUI and a Core Audio process tap that leaves normal playback active.

```sh
zsh test.sh
```

Checks cover stereo encoding at 44.1/48 kHz, file finalization, reel timing, hotkey registration, and shortcut persistence. A real Safari tone was also captured with built-in speakers; the saved file was independently decoded, and output-device switching was checked separately. These are local observations. Physical hotkey presses and other audio devices still need manual validation on the target Mac.

| Source | Responsibility |
| --- | --- |
| [`KolChenApp.swift`](Sources/KolChenApp.swift) | App lifecycle, recording state, menus |
| [`AudioRecorder.swift`](Sources/AudioRecorder.swift) | Native capture and asynchronous AAC encoding |
| [`CassetteView.swift`](Sources/CassetteView.swift) | Cassette UI and settings |
| [`RecordingShortcuts.swift`](Sources/RecordingShortcuts.swift) | Configurable global hotkeys |
| [`ReelMotion.swift`](Sources/ReelMotion.swift) | Recording-driven reel motion |

See [local branding](docs/branding.md) and [media provenance](docs/media/README.md).

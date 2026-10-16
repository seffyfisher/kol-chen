# kol-chen · קול-חן

<img src="docs/app-icon.png" width="144" alt="kol-chen cassette icon">

A small native macOS app for recording the sound playing on your computer while you keep listening. Built with SwiftUI and Core Audio, with a dark cassette interface.

אפליקציית מק קטנה להקלטת השמע שמתנגן במחשב, בלי להפסיק להאזין.

## Features

- Capture website and application audio to stereo AAC `.m4a` files.
- Keep playback on your usual speakers or headphones. No virtual audio device is required.
- Configure separate global keyboard shortcuts for starting and stopping.
- Watch the cassette reels rotate while recording, with real stereo level meters.
- Choose a save folder, play the last take, and open saved recordings in Finder.
- Continue recording with the window closed, using the menu bar controls.
- Record locally; no uploads, account, microphone access, or network service.

The recorder captures all system playback, so sounds from other apps can be included. Protected media may prevent capture.

## Build and run

Requires an Apple Silicon Mac, macOS 15 or later, and Xcode with Swift 6.

```sh
git clone https://github.com/seffyfisher/kol-chen.git
cd kol-chen
zsh build.sh
open build/kol-chen.app
```

The script creates a locally signed app. It does not notarize or install it.

1. Open the app and click the red record button.
2. Allow system audio recording when macOS requests it.
3. Play audio on a website or in another app.
4. Click the square stop icon to finish and save the recording.

If needed, check **System Settings → Privacy & Security → Screen & System Audio Recording** for **קול-חן**, then reopen the app.

Recordings default to `~/Music/kol-chen`. The gear button opens settings for the save folder and shortcuts.

## Keyboard shortcuts

| Action | Default |
| --- | --- |
| Start recording | Control–Option–Command–R |
| Stop and save | Control–Option–Command–S |

Change either combination in Settings. Shortcuts work while other apps are active and persist between launches. No Accessibility or Input Monitoring permission is needed.

## Validation

```sh
zsh test.sh
```

The checks exercise stereo encoding at 44.1/48 kHz with planar/interleaved input, safe file finalization, reel timing, hotkey registration and dispatch, conflicts, and shortcut persistence. Physical keyboard presses and real audio routes still need a manual check.

The recording engine was also tested on a Mac with built-in speakers: a tone played in Safari was captured through the installed app and the saved stereo file was independently decoded to verify actual audio. Output switching from a multi-output device to the built-in speakers was checked separately. These are local observations, not a claim about every audio device or protected player.

## Artwork and branding

The public app and icon use native system lettering. Private trial-font wordmarks, font binaries, personal recordings, and local settings are excluded.

To use your own appropriately licensed branding locally, add `Resources/kol-chen-logo.pdf` before building. That optional file is ignored by Git. `MakeWordmark.swift` can turn a font you are licensed to use into vector artwork:

```sh
xcrun swift MakeWordmark.swift /path/to/licensed-font.otf Resources
```

To regenerate the cassette app icon:

```sh
mkdir -p build
xcrun swift MakeIcon.swift build/kol-chen.iconset
iconutil -c icns build/kol-chen.iconset -o AppIcon.icns
```

## Source map

- `Sources/KolChenApp.swift`: app lifecycle, recording state, and menus.
- `Sources/AudioRecorder.swift`: native process tap and asynchronous AAC writer.
- `Sources/CassetteView.swift`: cassette interface and settings.
- `Sources/RecordingShortcuts.swift`: configurable global hotkeys.
- `Sources/ReelMotion.swift`: recording-driven reel rotation.

The capture path follows Apple's [Core Audio taps API](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps). The private capture device is never selected as the system output.

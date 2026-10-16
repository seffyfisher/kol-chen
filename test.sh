#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
CHECK_DIR="$PROJECT_DIR/build/checks"
mkdir -p "$CHECK_DIR" "$PROJECT_DIR/build/module-cache"
SWIFT_FLAGS=(-O -swift-version 6 -parse-as-library -module-cache-path "$PROJECT_DIR/build/module-cache")
xcrun swiftc "${SWIFT_FLAGS[@]}" "$PROJECT_DIR/Sources/AudioRecorder.swift" "$PROJECT_DIR/Tests/EncoderCheck.swift" -o "$CHECK_DIR/encoder"
"$CHECK_DIR/encoder" "$CHECK_DIR/encoder-output"
xcrun swiftc "${SWIFT_FLAGS[@]}" "$PROJECT_DIR/Sources/ReelMotion.swift" "$PROJECT_DIR/Tests/ReelMotionCheck.swift" -o "$CHECK_DIR/reels"
"$CHECK_DIR/reels"
xcrun swiftc "${SWIFT_FLAGS[@]}" "$PROJECT_DIR/Sources/RecordingShortcuts.swift" "$PROJECT_DIR/Tests/ShortcutCheck.swift" -o "$CHECK_DIR/shortcuts"
"$CHECK_DIR/shortcuts"

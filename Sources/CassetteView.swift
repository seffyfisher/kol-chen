import AppKit
import SwiftUI

enum AppBrand {
    // Separate visible branding from the bundle identity and existing save paths.
    static let name = "קול-חן"
}

@MainActor
private enum CassetteArtwork {
    static let body = load("CassetteBody")
    static let reel = load("CassetteReel")
    // A locally supplied, licensed wordmark is optional. Public builds use native type.
    static let logo = Bundle.main.url(forResource: "kol-chen-logo", withExtension: "pdf")
        .flatMap { NSImage(contentsOf: $0) }

    private static func load(_ name: String, extension fileExtension: String = "png") -> NSImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing required cassette artwork: \(name)")
        }
        return image
    }
}

struct CassetteRecorderView: View {
    @Bindable var model: RecorderModel
    let shortcuts: RecordingShortcuts

    var body: some View {
        VStack(spacing: 0) {
            CassetteBay(model: model)
                .frame(width: 504, height: 252)
                .padding(.horizontal, 18)
                .padding(.top, 8)

            HStack(alignment: .top, spacing: 18) {
                Button { model.playLast() } label: {
                    VStack(spacing: 7) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 24))
                            .frame(width: 76, height: 64)
                        Text("Last take").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.78))
                }
                .buttonStyle(CassetteSecondaryButtonStyle())
                .disabled(model.lastRecording == nil || model.phase != .ready)
                .help("Play the last saved recording")
                .accessibilityLabel("Play last recording")

                Button { model.toggleRecording() } label: {
                    Group {
                        if model.isBusy {
                            ProgressView().controlSize(.regular).tint(.white)
                        } else {
                            Image(systemName: model.isRecording ? "stop.fill" : "circle.fill")
                                .font(.system(size: 29, weight: .medium))
                        }
                    }
                    .foregroundStyle(Color(red: 0.97, green: 0.94, blue: 0.88))
                    .frame(width: 252, height: 76)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(CassetteRecordButtonStyle())
                .disabled(model.isBusy)
                .accessibilityLabel(model.isRecording ? "Stop and save recording" : "Start recording computer audio")
                .help(transportHelp)

                Button { model.openFolder() } label: {
                    VStack(spacing: 7) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 25))
                            .frame(width: 76, height: 64)
                        Text("Recordings").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.78))
                }
                .buttonStyle(CassetteSecondaryButtonStyle())
                .help(model.folder.path)
                .accessibilityLabel("Open recordings folder")
                .contextMenu {
                    Button("Show latest recording in Finder") { model.revealLast() }
                        .disabled(model.lastRecording == nil)
                    Button("Change recording folder…") { model.chooseFolder() }
                        .disabled(model.phase != .ready)
                }
            }
            .padding(.top, 22)
            .padding(.bottom, 22)
        }
        .frame(width: 540)
        .background(Color(red: 0.15, green: 0.155, blue: 0.16).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .toolbar {
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.flexible)
                ToolbarItem(placement: .primaryAction) { settingsControl }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItemGroup {
                    Spacer()
                    settingsControl
                }
            }
        }
        .toolbarBackground(Color(red: 0.15, green: 0.155, blue: 0.16), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .alert(AppBrand.name, isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("Audio Permissions…") { model.openAudioSettings() }
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var transportHelp: String {
        let action: RecordingAction = model.isRecording ? .stop : .start
        if let shortcut = shortcuts.preferences[action] { return "\(action.title) (\(shortcut.label))" }
        return action.title
    }

    private var settingsControl: some View {
        SettingsLink {
            Image(systemName: "gearshape.fill")
                .foregroundStyle(.white.opacity(0.62))
        }
        .buttonStyle(.plain)
        .help("Keyboard shortcuts and recording folder")
        .accessibilityLabel("Settings")
    }
}

private struct CassetteBay: View {
    let model: RecorderModel

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                Image(nsImage: CassetteArtwork.body)
                    .resizable()
                    .accessibilityHidden(true)

                CassetteReels(isRecording: model.isRecording)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: height * 0.76)
                    }

                Group {
                    if let logo = CassetteArtwork.logo {
                        Image(nsImage: logo)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Text(AppBrand.name)
                            .font(.system(size: 31, weight: .bold))
                            .foregroundStyle(Color(white: 0.93))
                    }
                }
                    .frame(width: 108, height: 34)
                    .accessibilityLabel(AppBrand.name)
                    .position(x: width * 0.50, y: height * 0.147)

                CassetteCounter(model: model)
                    .frame(width: width * 0.215)
                    .position(x: width * 0.50, y: height * 0.55)

                CassetteMeters(model: model)
                    .frame(width: width * 0.68)
                    .position(x: width * 0.50, y: height * 0.883)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

private struct CassetteReels: View {
    let isRecording: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = ReelMotion()

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isRecording || reduceMotion)) { _ in
                let angle = motion.angle()
                ZStack {
                    reel(angle: angle, width: width)
                        .position(x: width * 0.238, y: height * 0.507)
                    reel(angle: angle + 32, width: width)
                        .position(x: width * 0.759, y: height * 0.507)
                }
            }
        }
        .accessibilityHidden(true)
        .onChange(of: isRecording, initial: true) { _, recording in
            motion.setRunning(recording && !reduceMotion)
        }
        .onChange(of: reduceMotion) { _, reduced in
            motion.setRunning(isRecording && !reduced)
        }
        .onAppear { motion.setRunning(isRecording && !reduceMotion) }
        .onDisappear { motion.setRunning(false) }
    }

    private func reel(angle: Double, width: CGFloat) -> some View {
        Image(nsImage: CassetteArtwork.reel)
            .resizable()
            .frame(width: width * 0.313, height: width * 0.313)
            .rotationEffect(.degrees(angle))
    }
}

private struct CassetteCounter: View {
    let model: RecorderModel

    var body: some View {
        VStack(spacing: 12) {
            Text(model.timerText)
                .font(.system(size: model.elapsed >= 3600 ? 16 : 22, weight: .regular, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color(red: 0.94, green: 0.92, blue: 0.84))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.18), lineWidth: 1))
                .accessibilityLabel("Recording time \(model.timerText)")
            HStack(spacing: 5) {
                Circle().fill(model.isRecording ? Color.red : Color(white: 0.35))
                    .frame(width: 7, height: 7)
                Text(stateLabel)
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(model.isRecording ? Color(red: 1, green: 0.27, blue: 0.22) : .secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.status)
        }
    }

    private var stateLabel: String {
        switch model.phase {
        case .ready: model.lastRecording == nil ? "READY" : "SAVED"
        case .starting: "STARTING"
        case .recording: "RECORDING"
        case .stopping: "SAVING"
        }
    }
}

private struct CassetteMeters: View {
    let model: RecorderModel

    var body: some View {
        VStack(spacing: 4) {
            meter(label: "L", level: model.levelLeft)
            meter(label: "R", level: model.levelRight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stereo audio level")
        .accessibilityValue(model.level > 0.02 ? "Sound detected" : "Silent")
    }

    private func meter(label: String, level: Float) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.65)).frame(width: 10)
            ForEach(0..<28, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(model.isRecording && Float(bar + 1) / 28 <= level ? color(for: bar) : Color.white.opacity(0.065))
                    .frame(height: 6)
            }
        }
    }

    private func color(for bar: Int) -> Color {
        if bar >= 25 { return Color(red: 0.96, green: 0.27, blue: 0.16) }
        if bar >= 20 { return Color(red: 0.95, green: 0.68, blue: 0.20) }
        return Color(red: 0.33, green: 0.86, blue: 0.29)
    }
}

private struct CassetteRecordButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(red: 0.65, green: 0.12, blue: 0.13) : Color(red: 0.79, green: 0.17, blue: 0.18),
                        in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CassetteSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.28)
            .contentShape(Rectangle())
    }
}

struct RecorderSettingsView: View {
    let model: RecorderModel
    let shortcuts: RecordingShortcuts

    var body: some View {
        VStack(spacing: 0) {
            ShortcutSettingsView(shortcuts: shortcuts)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("Save recordings to").font(.headline)
                HStack {
                    Text(model.folder.path).font(.callout).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.middle)
                    Spacer(minLength: 12)
                    Button("Change…") { model.chooseFolder() }.disabled(model.phase != .ready)
                }
                Text("M4A audio · Microphone off · Playback stays on")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 460, alignment: .leading)
        }
        .frame(width: 460)
        .preferredColorScheme(.dark)
    }
}

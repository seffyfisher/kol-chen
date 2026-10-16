import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class RecorderModel {
    enum Phase: Equatable { case ready, starting, recording, stopping }
    private(set) var phase: Phase = .ready
    private(set) var elapsed: Double = 0
    private(set) var level: Float = 0
    private(set) var levelLeft: Float = 0
    private(set) var levelRight: Float = 0
    private(set) var hasHeardAudio = false
    private(set) var lastRecording: URL?
    private(set) var folder: URL
    var errorMessage: String?

    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private var currentURL: URL?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: "recordingFolder") {
            folder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            folder = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("kol-chen", isDirectory: true)
        }
        if let path = defaults.string(forKey: "lastRecording"), FileManager.default.fileExists(atPath: path) {
            lastRecording = URL(fileURLWithPath: path)
        }
    }

    var isRecording: Bool { phase == .recording }
    var isBusy: Bool { phase == .starting || phase == .stopping }
    var timerText: String {
        let seconds = max(0, Int(elapsed))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    var status: String {
        switch phase {
        case .ready: lastRecording == nil ? "Ready when you are" : "Your recording is saved"
        case .starting: "Waiting for audio permission…"
        case .stopping: "Saving your recording…"
        case .recording: hasHeardAudio ? "Recording computer audio" : "Listening for website audio…"
        }
    }

    func toggleRecording() {
        guard !isBusy else { return }
        if isRecording { Task { await stopRecording() } }
        else { Task { await startRecording() } }
    }

    func perform(_ action: RecordingAction) {
        switch action {
        case .start:
            guard phase == .ready else { return }
            Task { await startRecording() }
        case .stop:
            guard phase == .recording else { return }
            Task { await stopRecording() }
        }
    }

    private func startRecording() async {
        guard phase == .ready else { return }
        phase = .starting
        errorMessage = nil
        elapsed = 0
        level = 0
        levelLeft = 0
        levelRight = 0
        hasHeardAudio = false
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "kol-chen \(formatter.string(from: Date())) \(UUID().uuidString.prefix(6)).m4a"
        let url = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await recorder.start(url: url)
            currentURL = url
            phase = .recording
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, let self else { return }
                    await self.refreshStats()
                }
            }
        } catch {
            phase = .ready
            errorMessage = error.localizedDescription
        }
    }

    private func refreshStats() async {
        guard phase == .recording else { return }
        let stats = await recorder.stats()
        // A stop may have happened while waiting for the recorder actor.
        guard phase == .recording else { return }
        if let stats {
            elapsed = stats.seconds
            hasHeardAudio = hasHeardAudio || stats.peak > 0.0001
            let scaled = stats.peak > 0 ? max(0, min(1, (20 * log10(stats.peak) + 60) / 60)) : 0
            level = max(scaled, level * 0.72)
            levelLeft = max(meterLevel(stats.peakLeft), levelLeft * 0.72)
            levelRight = max(meterLevel(stats.peakRight), levelRight * 0.72)
            if stats.error != noErr { await stopRecording() }
        }
    }

    private func meterLevel(_ peak: Float) -> Float {
        peak > 0 ? max(0, min(1, (20 * log10(peak) + 60) / 60)) : 0
    }

    func stopRecording() async {
        guard phase == .recording else { return }
        phase = .stopping
        ticker?.cancel()
        ticker = nil
        do {
            let stats = try await recorder.stop()
            if let stats { elapsed = stats.seconds }
            finishTake()
            if stats?.frames == 0 {
                errorMessage = "No audio arrived. Play audio on the website, then try again. If it stays silent, allow \(AppBrand.name) in System Settings → Privacy & Security → Screen & System Audio Recording, and reopen the app."
            } else if !hasHeardAudio {
                errorMessage = "The recording contains silence. Make sure the website is playing sound and \(AppBrand.name) has system audio permission. Some protected players may prevent capture."
            }
        } catch {
            // A write/finalization error can still leave a playable partial take.
            // If capture could not be stopped, keep the Stop button available.
            if await recorder.isRunning {
                phase = .recording
            } else {
                finishTake()
            }
            errorMessage = error.localizedDescription
        }
    }

    private func finishTake() {
        if let currentURL, FileManager.default.fileExists(atPath: currentURL.path) {
            lastRecording = currentURL
            UserDefaults.standard.set(currentURL.path, forKey: "lastRecording")
        }
        currentURL = nil
        phase = .ready
        level = 0
        levelLeft = 0
        levelRight = 0
    }

    func chooseFolder() {
        guard phase == .ready else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose where \(AppBrand.name) saves recordings"
        panel.prompt = "Choose Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url {
            folder = url
            UserDefaults.standard.set(url.path, forKey: "recordingFolder")
        }
    }

    func openFolder() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        } catch { errorMessage = error.localizedDescription }
    }

    func playLast() {
        guard let lastRecording else { return }
        NSWorkspace.shared.open(lastRecording)
    }

    func revealLast() {
        guard let lastRecording else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastRecording])
    }

    func openAudioSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func prepareToQuit() async -> Bool {
        while isBusy { try? await Task.sleep(for: .milliseconds(100)) }
        if isRecording { await stopRecording() }
        return phase == .ready
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: RecorderModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.phase != .ready else { return .terminateNow }
        Task { sender.reply(toApplicationShouldTerminate: await model.prepareToQuit()) }
        return .terminateLater
    }
}

@main
struct KolChenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = RecorderModel()
    @State private var shortcuts = RecordingShortcuts()

    var body: some Scene {
        Window(AppBrand.name, id: "recorder") {
            CassetteRecorderView(model: model, shortcuts: shortcuts)
                .onAppear {
                    delegate.model = model
                    shortcuts.activate { [weak recorderModel = model] action in recorderModel?.perform(action) }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Recording") {
                Button(model.isRecording ? "Stop and Save" : "Record Computer Audio") { model.toggleRecording() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.isBusy)
                SettingsLink { Text("Keyboard Shortcuts…") }
                Button("Open Recordings Folder") { model.openFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
        Settings {
            RecorderSettingsView(model: model, shortcuts: shortcuts)
        }
        .windowResizability(.contentSize)
        MenuBarExtra {
            StatusMenu(model: model)
        } label: {
            Image(systemName: model.isRecording ? "record.circle.fill" : "waveform.circle")
                .accessibilityLabel(model.isRecording ? "kol-chen is recording" : AppBrand.name)
        }
    }
}

private struct StatusMenu: View {
    let model: RecorderModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.isRecording ? "Recording · \(model.timerText)" : AppBrand.name)
        Button(model.isRecording ? "Stop and Save" : "Record Computer Audio") { model.toggleRecording() }
            .disabled(model.isBusy)
        Button("Show \(AppBrand.name)") {
            openWindow(id: "recorder")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Open Recordings Folder") { model.openFolder() }
        SettingsLink { Text("Keyboard Shortcuts…") }
        Divider()
        Button(model.isRecording ? "Save and Quit \(AppBrand.name)" : "Quit \(AppBrand.name)") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

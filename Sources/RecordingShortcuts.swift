import AppKit
import Carbon
import Observation
import SwiftUI

enum RecordingAction: UInt32, CaseIterable, Identifiable, Sendable {
    case start = 1, stop = 2
    var id: UInt32 { rawValue }
    var title: String { self == .start ? "Start recording" : "Stop and save" }
}

struct KeyCombination: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    var label: String {
        var result = ""
        for (flag, symbol) in [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")] {
            if modifiers & UInt32(flag) != 0 { result += symbol }
        }
        return result + keyLabel
    }

    func matches(_ other: Self) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }

    static func from(_ event: NSEvent) -> Self? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Require Command or Control so normal typing and accent entry stay usable.
        guard flags.contains(.command) || flags.contains(.control) else { return nil }
        var modifiers: UInt32 = 0
        for (flag, carbon) in [(NSEvent.ModifierFlags.command, cmdKey), (.control, controlKey), (.option, optionKey), (.shift, shiftKey)] {
            if flags.contains(flag) { modifiers |= UInt32(carbon) }
        }
        let special: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤",
            115: "↖", 116: "⇞", 117: "⌦", 119: "↘", 121: "⇟",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"
        ]
        let label = special[event.keyCode] ?? event.characters(byApplyingModifiers: [])?.uppercased() ?? ""
        guard !label.isEmpty, !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return Self(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label)
    }
}

struct ShortcutPreferences: Codable, Equatable, Sendable {
    var start: KeyCombination?
    var stop: KeyCombination?
    static let defaults = Self(
        start: KeyCombination(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(controlKey | optionKey | cmdKey), keyLabel: "R"),
        stop: KeyCombination(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey | cmdKey), keyLabel: "S")
    )

    subscript(action: RecordingAction) -> KeyCombination? {
        get { action == .start ? start : stop }
        set { if action == .start { start = newValue } else { stop = newValue } }
    }

    func validate() throws {
        if let start, let stop, start.matches(stop) {
            throw ShortcutError(message: "Start and Stop need different shortcuts.")
        }
        for shortcut in [start, stop].compactMap({ $0 }) {
            let supported = UInt32(controlKey | optionKey | shiftKey | cmdKey)
            guard shortcut.keyCode <= 127,
                  shortcut.modifiers & UInt32(controlKey | cmdKey) != 0,
                  shortcut.modifiers & ~supported == 0 else {
                throw ShortcutError(message: "Include ⌘ Command or ⌃ Control in your shortcut.")
            }
        }
    }
}

struct ShortcutError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Registers only the selected combinations with macOS. This does not monitor
/// keys in other apps and does not require Accessibility or Input Monitoring.
@MainActor
final class GlobalHotKeyRegistry {
    nonisolated static let signature: OSType = 0x4B43484E // KCHN
    private var handler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private var registeredActions: Set<RecordingAction> = []
    let onAction: @MainActor (RecordingAction) -> Void

    init(onAction: @escaping @MainActor (RecordingAction) -> Void) throws {
        self.onAction = onAction
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == GlobalHotKeyRegistry.signature,
                  let action = RecordingAction(rawValue: identifier.id) else { return OSStatus(eventNotHandledErr) }
            // Application-target Carbon events are delivered on the main event loop.
            return MainActor.assumeIsolated {
                let registry = Unmanaged<GlobalHotKeyRegistry>.fromOpaque(context).takeUnretainedValue()
                guard registry.registeredActions.contains(action) else { return OSStatus(eventNotHandledErr) }
                registry.onAction(action)
                return noErr
            }
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { throw ShortcutError(message: "Could not enable keyboard shortcuts (\(status)).") }
    }

    func configure(_ preferences: ShortcutPreferences) throws {
        try preferences.validate()
        unregister()
        do {
            for action in RecordingAction.allCases {
                guard let shortcut = preferences[action] else { continue }
                var reference: EventHotKeyRef?
                let identifier = EventHotKeyID(signature: Self.signature, id: action.rawValue)
                let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier,
                                                GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
                guard status == noErr, let reference else {
                    throw ShortcutError(message: "\(shortcut.label) is unavailable for \(action.title.lowercased()). Choose another combination. (\(status))")
                }
                hotKeys.append(reference)
                registeredActions.insert(action)
            }
        } catch {
            unregister()
            throw error
        }
    }

    func unregister() {
        for reference in hotKeys { UnregisterEventHotKey(reference) }
        hotKeys.removeAll()
        registeredActions.removeAll()
    }

    isolated deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }
}

@MainActor @Observable
final class RecordingShortcuts {
    private(set) var preferences: ShortcutPreferences
    private(set) var capturing: RecordingAction?
    private(set) var message: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var registry: GlobalHotKeyRegistry?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var focusObserver: NSObjectProtocol?
    @ObservationIgnored private var captureID: UUID?
    static let storageKey = "globalRecordingShortcuts.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(ShortcutPreferences.self, from: data),
           (try? stored.validate()) != nil {
            preferences = stored
        } else { preferences = .defaults }
    }

    func activate(onAction: @escaping @MainActor (RecordingAction) -> Void) {
        guard registry == nil else { return }
        do {
            registry = try GlobalHotKeyRegistry(onAction: onAction)
            try registry?.configure(preferences)
        } catch { message = error.localizedDescription }
    }

    func beginCapture(_ action: RecordingAction) {
        cancelCapture()
        message = nil
        capturing = action
        registry?.unregister() // Existing shortcuts must not record while being edited.
        let identifier = UUID()
        captureID = identifier
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, self.capturing != nil else { return false }
                if event.isARepeat { return true }
                let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
                if event.keyCode == 53, flags.isEmpty { self.cancelCapture(); return true }
                if [UInt16(51), UInt16(117)].contains(event.keyCode), flags.isEmpty {
                    self.assign(nil, to: action)
                    return true
                }
                guard let shortcut = KeyCombination.from(event) else {
                    self.message = "Hold ⌘ Command or ⌃ Control with your chosen key. Escape cancels."
                    return true
                }
                self.assign(shortcut, to: action)
                return true
            }
            return consumed ? nil : event
        }
        focusObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                               object: NSApp.keyWindow, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.captureID == identifier else { return }
                self?.cancelCapture()
            }
        }
    }

    func assign(_ shortcut: KeyCombination?, to action: RecordingAction) {
        var proposed = preferences
        proposed[action] = shortcut
        apply(proposed)
    }

    func restoreDefaults() { apply(.defaults) }

    private func apply(_ proposed: ShortcutPreferences) {
        do { try proposed.validate() }
        catch { message = error.localizedDescription; return }
        endCapture()
        do {
            try registry?.configure(proposed)
            let data = try JSONEncoder().encode(proposed)
            preferences = proposed
            defaults.set(data, forKey: Self.storageKey)
            message = nil
        } catch {
            message = error.localizedDescription
            do { try registry?.configure(preferences) }
            catch { message = "\(message ?? "") The previous shortcuts could not be restored. Choose new shortcuts." }
        }
    }

    func cancelCapture() {
        guard capturing != nil else { return }
        endCapture()
        do { try registry?.configure(preferences) }
        catch { message = error.localizedDescription }
    }

    private func endCapture() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
        keyMonitor = nil
        focusObserver = nil
        captureID = nil
        capturing = nil
    }
}

struct ShortcutSettingsView: View {
    let shortcuts: RecordingShortcuts

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Keyboard Shortcuts", systemImage: "keyboard")
                    .font(.title2.weight(.semibold))
                Text("Start and stop recording while your browser or any other app is active.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 16) {
                ForEach(RecordingAction.allCases) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        Button {
                            if shortcuts.capturing == action { shortcuts.cancelCapture() }
                            else { shortcuts.beginCapture(action) }
                        } label: {
                            Text(shortcuts.capturing == action ? "Press shortcut…" : (shortcuts.preferences[action]?.label ?? "Set Shortcut"))
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 155, height: 24)
                        }
                        .tint(shortcuts.capturing == action ? .accentColor : nil)
                        .accessibilityLabel("\(action.title) shortcut")
                        .accessibilityValue(shortcuts.capturing == action ? "Waiting for keys" : (shortcuts.preferences[action]?.label ?? "Not set"))
                        Button { shortcuts.assign(nil, to: action) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(shortcuts.preferences[action] == nil)
                        .help("Disable \(action.title.lowercased()) shortcut")
                        .accessibilityLabel("Disable \(action.title.lowercased()) shortcut")
                    }
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            Text(shortcuts.capturing == nil
                 ? "Click a shortcut, then press the new combination. Include ⌘ or ⌃."
                 : "Press your shortcut now. Escape cancels; Delete disables it.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let message = shortcuts.message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("Changes save automatically.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Restore Defaults") { shortcuts.restoreDefaults() }
            }
        }
        .padding(24)
        .frame(width: 460)
        .onDisappear { shortcuts.cancelCapture() }
    }
}

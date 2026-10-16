import AppKit
import Carbon
import Foundation

@main
struct ShortcutCheck {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let flags = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        let start = KeyCombination(keyCode: UInt32(kVK_F18), modifiers: flags, keyLabel: "F18")
        let stop = KeyCombination(keyCode: UInt32(kVK_F19), modifiers: flags, keyLabel: "F19")
        let preferences = ShortcutPreferences(start: start, stop: stop)
        try preferences.validate()
        do {
            let samePhysicalKey = KeyCombination(keyCode: start.keyCode, modifiers: flags, keyLabel: "Different display label")
            try ShortcutPreferences(start: start, stop: samePhysicalKey).validate()
            fatalError("Duplicate physical combinations must fail")
        } catch is ShortcutError { print("PASS: duplicate combinations rejected") }
        do {
            try ShortcutPreferences(start: KeyCombination(keyCode: 0, modifiers: UInt32(shiftKey), keyLabel: "A"), stop: nil).validate()
            fatalError("Plain typing combinations must fail")
        } catch is ShortcutError { print("PASS: shortcuts require Command or Control") }

        var actions: [RecordingAction] = []
        let registry = try GlobalHotKeyRegistry { actions.append($0) }
        try registry.configure(preferences)
        let competing = try GlobalHotKeyRegistry { _ in }
        do {
            try competing.configure(preferences)
            fatalError("Exclusive registrations must detect conflicts")
        } catch is ShortcutError { print("PASS: another registration's conflict detected") }
        for action in RecordingAction.allCases {
            var event: EventRef?
            precondition(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, EventAttributes(kEventAttributeNone), &event) == noErr)
            let created = event!
            defer { ReleaseEvent(created) }
            var identifier = EventHotKeyID(signature: GlobalHotKeyRegistry.signature, id: action.rawValue)
            precondition(SetEventParameter(created, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout.size(ofValue: identifier), &identifier) == noErr)
            precondition(SendEventToEventTarget(created, GetApplicationEventTarget()) == noErr)
        }
        precondition(actions == [.start, .stop])
        print("PASS: native event dispatch reaches separate Start and Stop actions")
        registry.unregister()
        try competing.configure(preferences)
        competing.unregister()
        print("PASS: unregister releases shortcuts for reuse")

        let suite = "com.seffyfisher.kol-chen.shortcuts-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = RecordingShortcuts(defaults: defaults)
        settings.assign(start, to: .start)
        settings.assign(stop, to: .stop)
        let reopened = RecordingShortcuts(defaults: defaults)
        precondition(reopened.preferences == preferences)
        reopened.assign(start, to: .stop)
        precondition(reopened.message != nil && reopened.preferences == preferences)
        reopened.assign(nil, to: .stop)
        precondition(RecordingShortcuts(defaults: defaults).preferences.stop == nil)
        reopened.restoreDefaults()
        precondition(RecordingShortcuts(defaults: defaults).preferences == .defaults)
        print("PASS: persistence, duplicate rollback, clearing, and restoring defaults")
    }
}

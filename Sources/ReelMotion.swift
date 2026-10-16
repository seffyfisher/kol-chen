import Foundation

/// A continuous, linear transport clock. Stopping preserves the current phase;
/// restarting resumes there instead of snapping the artwork back to zero.
struct ReelMotion {
    private(set) var accumulated: Duration = .zero
    private(set) var startedAt: ContinuousClock.Instant?
    static let secondsPerRevolution = 5.0

    mutating func setRunning(_ running: Bool, at now: ContinuousClock.Instant = .now) {
        if running {
            if startedAt == nil { startedAt = now }
        } else if let startedAt {
            accumulated += startedAt.duration(to: now)
            self.startedAt = nil
        }
    }

    func angle(at now: ContinuousClock.Instant = .now) -> Double {
        let elapsed = accumulated + (startedAt?.duration(to: now) ?? .zero)
        let components = elapsed.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return (seconds / Self.secondsPerRevolution * 360).truncatingRemainder(dividingBy: 360)
    }
}

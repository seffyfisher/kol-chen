import Foundation

@main
struct ReelMotionCheck {
    static func main() {
        let zero = ContinuousClock.now
        var motion = ReelMotion()
        precondition(motion.angle(at: zero) == 0)
        motion.setRunning(true, at: zero)
        precondition(abs(motion.angle(at: zero.advanced(by: .seconds(1))) - 72) < 0.001)
        // Repeated recording updates must not restart the transport clock.
        motion.setRunning(true, at: zero.advanced(by: .seconds(1)))
        precondition(abs(motion.angle(at: zero.advanced(by: .seconds(2))) - 144) < 0.001)
        motion.setRunning(false, at: zero.advanced(by: .seconds(2)))
        precondition(abs(motion.angle(at: zero.advanced(by: .seconds(60))) - 144) < 0.001)
        motion.setRunning(true, at: zero.advanced(by: .seconds(60)))
        precondition(abs(motion.angle(at: zero.advanced(by: .seconds(61))) - 216) < 0.001)
        motion.setRunning(false, at: zero.advanced(by: .seconds(61)))
        precondition(abs(motion.angle(at: zero.advanced(by: .seconds(300))) - 216) < 0.001)
        print("PASS: linear reel motion, stable stop, continuous resume, no idle drift")
    }
}

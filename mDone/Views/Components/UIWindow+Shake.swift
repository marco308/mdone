#if os(iOS)
import CoreMotion
import UIKit

extension UIWindow {
    static let deviceDidShakeNotification = Notification.Name("com.mdone.deviceDidShake")
}

/// Posts `UIWindow.deviceDidShakeNotification` when the user shakes the device.
///
/// Uses CoreMotion's raw accelerometer feed instead of `UIResponder.motionEnded`
/// because the responder-chain path proved unreliable: SwiftUI re-renders and
/// keyboard transitions silently steal first-responder status, and iOS 18+
/// frequently doesn't propagate the motion event up to `UIWindow.motionEnded`
/// at all. Accelerometer sampling sees every shake (#82).
final class ShakeDetector {
    private let motionManager = CMMotionManager()
    private var lastShakeFire: Date = .distantPast
    private let threshold: Double = 1.8 // total g-force above 1g baseline
    private let cooldown: TimeInterval = 1.0

    func start() {
        guard motionManager.isAccelerometerAvailable else { return }
        guard !motionManager.isAccelerometerActive else { return }
        motionManager.accelerometerUpdateInterval = 1.0 / 30.0
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let magnitude = sqrt(
                data.acceleration.x * data.acceleration.x
                    + data.acceleration.y * data.acceleration.y
                    + data.acceleration.z * data.acceleration.z
            )
            // Magnitude of ~1.0 is gravity at rest; shakes spike well above.
            if magnitude > self.threshold {
                let now = Date()
                if now.timeIntervalSince(self.lastShakeFire) > self.cooldown {
                    self.lastShakeFire = now
                    NotificationCenter.default.post(
                        name: UIWindow.deviceDidShakeNotification,
                        object: nil
                    )
                }
            }
        }
    }

    func stop() {
        if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
        }
    }

    deinit {
        if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
        }
    }
}
#endif

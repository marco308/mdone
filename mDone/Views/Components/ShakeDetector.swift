#if os(iOS)
import SwiftUI
import UIKit

extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name("mDone.deviceDidShake")
}

extension UIWindow {
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
    }
}

private struct DeviceShakeViewModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
            // iPhone-only feature (issue #82); ignore shakes on iPad.
            guard UIDevice.current.userInterfaceIdiom == .phone else { return }
            action()
        }
    }
}

extension View {
    /// Runs `action` when the device is physically shaken. iPhone only.
    func onShake(perform action: @escaping () -> Void) -> some View {
        modifier(DeviceShakeViewModifier(action: action))
    }
}
#endif

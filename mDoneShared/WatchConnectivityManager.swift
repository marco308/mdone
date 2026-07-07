#if os(iOS) || os(watchOS)
import Foundation
import WatchConnectivity
import Combine

public class WatchConnectivityManager: NSObject, WCSessionDelegate, ObservableObject {
    public static let shared = WatchConnectivityManager()
    
    @Published public var isConnected = false
    @Published public var syncedServerURL: String?
    @Published public var syncedToken: String?
    
    private override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }
    
    #if os(iOS)
    public func syncCredentials(serverURL: String, token: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let payload = ["serverURL": serverURL, "apiToken": token]
        
        // Use transferUserInfo as a highly reliable fallback for simulators and initial setup.
        // It queues the data even if the session isn't fully activated yet.
        session.transferUserInfo(payload)
        print("mDone: Enqueued transferUserInfo to Apple Watch")
        
        if session.activationState == .activated && session.isWatchAppInstalled {
            do {
                try session.updateApplicationContext(payload)
                print("mDone: Updated Application Context for Apple Watch")
            } catch {
                print("mDone: Failed to sync credentials via context: \(error)")
            }
        } else {
            print("mDone: Cannot update application context because activationState=\(session.activationState.rawValue), isWatchAppInstalled=\(session.isWatchAppInstalled)")
        }
    }
    #endif
    
    // MARK: - WCSessionDelegate
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = (activationState == .activated)
            
            #if os(iOS)
            // En iOS, si acabamos de activarnos y tenemos sesión, la enviamos por si acaso
            if session.isWatchAppInstalled {
                if let url = UserDefaults.standard.string(forKey: "com.mdone.serverURL"),
                   let token = SharedTokenStore.get() {
                    self.syncCredentials(serverURL: url, token: token)
                }
            }
            #endif
        }
    }
    
    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif
    
    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleReceivedContext(applicationContext)
    }
    
    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handleReceivedContext(userInfo)
    }
    
    private func handleReceivedContext(_ context: [String: Any]) {
        DispatchQueue.main.async {
            if let serverURL = context["serverURL"] as? String {
                self.syncedServerURL = serverURL
                SharedKeys.sharedDefaults.set(serverURL, forKey: SharedKeys.serverURLKey)
            }
            if let apiToken = context["apiToken"] as? String {
                self.syncedToken = apiToken
                SharedTokenStore.save(apiToken)
            }
        }
    }
}
#endif

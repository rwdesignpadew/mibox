import GoogleCast
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let configuredReceiverID = Bundle.main.object(forInfoDictionaryKey: "CastReceiverApplicationID") as? String
        let receiverID = configuredReceiverID.flatMap { $0.isEmpty ? nil : $0 }
            ?? kGCKDefaultMediaReceiverApplicationID
        let criteria = GCKDiscoveryCriteria(applicationID: receiverID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.suspendSessionsWhenBackgrounded = false
        GCKCastContext.setSharedInstanceWith(options)
        GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = true
        return true
    }
}

@main
struct MiBoxScreenApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

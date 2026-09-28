import AppIntents
import CopilotCore
import SwiftUI
import UIKit

/// iOS app entry point and composition root (the only place that picks concrete implementations).
///
/// The iPhone is the camera and attachment manager (spec 17); answers are read on the Watch.
@main
struct CopilotApp: App {
 /// Bridge to the UIKit app delegate: needed for background upload events (see AppDelegate).
 @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
 @State private var store: DraftStore? = CopilotApp.makeStore()
 @State private var showCamera = false
 @Environment(\.scenePhase) private var scenePhase

 var body: some Scene {
  WindowGroup {
   if let store {
    DraftView(showCamera: $showCamera)
     .environment(store)
     .fullScreenCover(isPresented: $showCamera) {
      CameraView().environment(store)
     }
     .task { await store.refresh() }
     .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      // "Ask with Camera" (Action Button / Control / Siri) asked for the camera.
      if PendingRoute.take() == .camera { showCamera = true }
      Task { await store.refresh() }
     }
   } else {
    ContentUnavailableView(
     "Backend not configured",
     systemImage: "server.rack",
     description: Text("Set COPILOT_HOST and COPILOT_DEVICE_TOKEN in Config/Signing.local.xcconfig and rebuild.")
    )
   }
  }
 }

 /// Real backend only: without it the iPhone app has nothing useful to do (no mock on iOS - YAGNI).
 private static func makeStore() -> DraftStore? {
  guard let configuration = BackendConfiguration.fromInfoPlist() else { return nil }
  let service = LiveCopilotService(baseURL: configuration.baseURL, deviceToken: configuration.deviceToken)
  return DraftStore(service: service) { onEvent in
   let uploads = UploadManager(baseURL: configuration.baseURL, deviceToken: configuration.deviceToken, onEvent: onEvent)
   UploadManager.shared = uploads
   return uploads
  }
 }
}

/// UIKit app delegate, only for background URLSession events: when uploads finish while the app is
/// suspended or terminated, iOS relaunches it in the background and hands over a completion handler
/// that must be called once all events are processed.
final class AppDelegate: NSObject, UIApplicationDelegate {

 func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
  completionHandler: @escaping () -> Void) {
  guard identifier == UploadManager.sessionIdentifier else {
   completionHandler()
   return
  }
  // The App struct (created before this call) already recreated the session with the same identifier,
  // which reconnects it to the finished transfers.
  let handler = UncheckedSendable(completionHandler)
  if let uploads = UploadManager.shared {
   uploads.setBackgroundCompletion { handler.value() }
  } else {
   completionHandler()
  }
 }
}

/// Wraps a non-Sendable UIKit closure that UIKit itself requires to be called on the main thread.
private struct UncheckedSendable<Value>: @unchecked Sendable {
 let value: Value
 init(_ value: Value) { self.value = value }
}

/// Registers "Ask with Camera" as an App Shortcut (Siri, Spotlight, Shortcuts app).
/// The intent itself lives in iOSShared/AskWithCameraIntent.swift. The Action Button route is the
/// Control in iOSWidgets (more reliable, see docs PI 2.4).
struct CopilotShortcuts: AppShortcutsProvider {
 static var appShortcuts: [AppShortcut] {
  AppShortcut(
   intent: AskWithCameraIntent(),
   phrases: ["Ask \(.applicationName) with camera"],
   shortTitle: "Ask with Camera",
   systemImageName: "camera"
  )
 }
}

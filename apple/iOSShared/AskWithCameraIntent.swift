import AppIntents
import Foundation

/// "Ask with Camera" (spec 19): opens the app directly on the camera.
///
/// Compiled into TWO targets (see project.yml, `iOSShared`):
/// - the iOS app, which performs it (opens itself and shows the camera);
/// - the iOS widget extension, whose Control references it.
/// The intent type must exist in both places so the system can match them.
struct AskWithCameraIntent: AppIntent {
 static let title: LocalizedStringResource = "Ask with Camera"
 static let description = IntentDescription("Opens the AI Copilot camera to photograph pages.")
 /// Run by launching the app in the foreground (Face ID unlock is part of the flow).
 static let openAppWhenRun = true

 func perform() async throws -> some IntentResult {
  // The app reads this when it becomes active and opens the camera (see CopilotApp).
  // UserDefaults instead of a direct call: this file also compiles into the widget extension,
  // which cannot reference app-only types.
  UserDefaults.standard.set(PendingRoute.camera.rawValue, forKey: PendingRoute.key)
  return .result()
 }
}

/// A navigation request handed from an App Intent to the app.
enum PendingRoute: String {
 case camera

 static let key = "pendingRoute"

 /// Returns and clears the pending route.
 static func take() -> PendingRoute? {
  let value = UserDefaults.standard.string(forKey: key).flatMap(PendingRoute.init(rawValue:))
  UserDefaults.standard.removeObject(forKey: key)
  return value
 }
}

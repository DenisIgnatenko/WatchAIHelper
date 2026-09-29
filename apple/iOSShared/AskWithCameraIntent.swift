import AppIntents
import Foundation

/// "Ask with Camera" (spec 19): opens the app directly on the photo picker. The app has no camera of its own since
/// 2026-09-29 (docs PI 4.4); the name and identifiers stay, so the Action Button setup keeps working.
///
/// An `OpenIntent` (not a plain `AppIntent` with `openAppWhenRun`): Apple's documentation requires
/// `OpenIntent` for a Control that must open its app ("Creating controls to perform actions across the system").
/// With a plain intent the iPhone Action Button ran the Control but the app never opened (device finding).
///
/// Compiled into TWO targets (see project.yml, `iOSShared`):
/// - the iOS app, which performs it (the system brings the app to the foreground first);
/// - the iOS widget extension, whose Control references it.
/// Apple requires the intent's target membership in both to open the app.
struct AskWithCameraIntent: OpenIntent {
 static let title: LocalizedStringResource = "Ask with Camera"
 static let description = IntentDescription("Opens AI Copilot to add photos of pages.")

 /// iOS 26+: explicitly bring the app to the foreground BEFORE `perform()` runs.
 /// Belt and braces next to `OpenIntent`, after the Control did not open the app on the device.
 static let supportedModes: IntentModes = .foreground(.immediate)

 /// `OpenIntent` needs a target: the screen to open. There is only one for now.
 @Parameter(title: "Screen")
 var target: CopilotScreen

 init() {
  target = .camera
 }

 func perform() async throws -> some IntentResult {
  // The app reads this when it becomes active and opens the camera (see CopilotApp).
  // UserDefaults instead of a direct call: this file also compiles into the widget extension,
  // which cannot reference app-only types.
  UserDefaults.standard.set(PendingRoute.camera.rawValue, forKey: PendingRoute.key)
  return .result()
 }
}

/// Screens an intent can open. `AppEnum` makes the values understandable to Shortcuts / Siri.
enum CopilotScreen: String, AppEnum {
 case camera

 static let typeDisplayRepresentation: TypeDisplayRepresentation = "Screen"
 static let caseDisplayRepresentations: [CopilotScreen: DisplayRepresentation] = [.camera: "Camera"]
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

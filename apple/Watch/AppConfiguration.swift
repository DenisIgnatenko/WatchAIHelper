import CopilotCore
import Foundation

/// Chooses the `CopilotService` implementation for this build (part of the composition root).
///
/// The backend address and device token come from Info.plist, which Xcode fills from
/// Config/Signing.local.xcconfig at build time (git-ignored). Interim solution until device pairing
/// through the iPhone exists (Phase 5); the token then moves to the Keychain.
enum AppConfiguration {

 static func makeService() -> any CopilotService {
  if LaunchOptions.demoConversation {
   return MockCopilotService(scenario: .photosReady(3), seedDemoConversation: true)
  }
  guard
   let host = infoValue("CopilotHost"),
   let token = infoValue("CopilotDeviceToken"),
   let baseURL = URL(string: "https://\(host)")
  else {
   // No backend configured: simulator and UI work keep running on the mock.
   return MockCopilotService(scenario: .photosUploading(3))
  }
  return LiveCopilotService(baseURL: baseURL, deviceToken: token)
 }

 /// A non-empty Info.plist string, or nil (unset xcconfig variables arrive as empty strings).
 private static func infoValue(_ key: String) -> String? {
  guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
  let trimmed = value.trimmingCharacters(in: .whitespaces)
  return trimmed.isEmpty ? nil : trimmed
 }
}

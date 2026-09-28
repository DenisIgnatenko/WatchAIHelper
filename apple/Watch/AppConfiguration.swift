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
  guard let configuration = BackendConfiguration.fromInfoPlist() else {
   // No backend configured: simulator and UI work keep running on the mock.
   return MockCopilotService(scenario: .photosUploading(3))
  }
  return LiveCopilotService(baseURL: configuration.baseURL, deviceToken: configuration.deviceToken)
 }
}

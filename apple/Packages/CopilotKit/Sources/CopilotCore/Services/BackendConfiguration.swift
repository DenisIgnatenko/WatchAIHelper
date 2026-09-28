import Foundation

/// Backend address and device token of this build, read from Info.plist
/// (filled from the git-ignored Config/Signing.local.xcconfig at build time).
///
/// Shared by the iOS and watchOS apps (DRY). Interim solution until device pairing exists (Phase 5).
public struct BackendConfiguration: Sendable {
 public let baseURL: URL
 public let deviceToken: String

 /// `nil` when the build has no backend configured (simulator, demos): the apps then use the mock.
 public static func fromInfoPlist(_ bundle: Bundle = .main) -> BackendConfiguration? {
  guard
   let host = value(bundle, "CopilotHost"),
   let token = value(bundle, "CopilotDeviceToken"),
   let url = URL(string: "https://\(host)")
  else { return nil }
  return BackendConfiguration(baseURL: url, deviceToken: token)
 }

 /// A non-empty Info.plist string, or nil (unset xcconfig variables arrive as empty strings).
 private static func value(_ bundle: Bundle, _ key: String) -> String? {
  guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
  let trimmed = raw.trimmingCharacters(in: .whitespaces)
  return trimmed.isEmpty ? nil : trimmed
 }
}

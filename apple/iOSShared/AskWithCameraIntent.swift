import AppIntents

/// "Ask with Camera" (spec 19). Phase 1: only opens the app; the camera screen comes in Phase 3.
///
/// Compiled into TWO targets (see project.yml, `iOSShared`):
/// - the iOS app, which performs it (opens itself);
/// - the iOS widget extension, whose Control references it.
/// The intent type must exist in both places so the system can match them.
struct AskWithCameraIntent: AppIntent {
 static let title: LocalizedStringResource = "Ask with Camera"
 static let description = IntentDescription("Opens the AI Copilot camera to photograph pages.")
 /// Run by launching the app in the foreground (Face ID unlock is part of the flow).
 static let openAppWhenRun = true

 func perform() async throws -> some IntentResult {
  .result()
 }
}

import AppIntents

/// "Ask AI": opens the Watch app on its main screen, where Ask is one tap away.
///
/// Compiled into TWO targets (see project.yml, `WatchShared`):
/// - the Watch app, which actually performs it (opens itself);
/// - the Watch widget extension, whose Control ("Ask AI" button) references it.
/// The intent type must exist in both places so the system can match them.
///
/// Opening the text input automatically is not possible: watchOS has no API to present
/// the system text input programmatically (only `TextFieldLink` / `TextField` do it on tap).
struct AskAIIntent: AppIntent {
 static let title: LocalizedStringResource = "Ask AI"
 static let description = IntentDescription("Opens AI Copilot to ask a question.")
 /// Run by launching the app in the foreground.
 static let openAppWhenRun = true

 func perform() async throws -> some IntentResult {
  .result()
 }
}

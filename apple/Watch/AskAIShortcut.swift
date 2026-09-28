import AppIntents

/// "Ask AI" action for Shortcuts / Siri and, through a user-made shortcut, the Ultra Action Button
/// (docs/phase-0/platform-investigation.md, section 7; device check V6).
///
/// It only opens the app on the main screen, where Ask is one tap away.
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

/// Registers the intent as an App Shortcut: available without any setup by the user
/// in Shortcuts, Siri and Spotlight.
struct CopilotWatchShortcuts: AppShortcutsProvider {
 static var appShortcuts: [AppShortcut] {
  AppShortcut(
   intent: AskAIIntent(),
   phrases: ["Ask \(.applicationName)"],
   shortTitle: "Ask AI",
   systemImageName: "sparkles"
  )
 }
}

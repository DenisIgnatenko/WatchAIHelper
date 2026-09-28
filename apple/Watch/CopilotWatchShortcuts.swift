import AppIntents

/// Registers "Ask AI" as an App Shortcut: available without setup in Siri, Spotlight and the Shortcuts app.
///
/// Note (verified on device, 2026-09-28): an App Shortcut of a watch app is NOT offered in
/// Settings > Action Button > Shortcut. The Action Button route is the Control in the
/// widget extension (WatchWidgets/AskAIControl.swift).
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

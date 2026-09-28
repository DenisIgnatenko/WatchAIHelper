import AppIntents
import SwiftUI

/// iOS app entry point.
///
/// Phase 1: a placeholder. It exists because a watchOS app is installed together with its iOS
/// companion, and to validate that an App Shortcut can be assigned to the iPhone Action Button
/// (device check V5). Camera, Photo Library and drafts arrive in Phases 3-4.
@main
struct CopilotApp: App {
 var body: some Scene {
  WindowGroup {
   PlaceholderView()
  }
 }
}

private struct PlaceholderView: View {
 var body: some View {
  ContentUnavailableView(
   "AI Copilot",
   systemImage: "applewatch",
   description: Text("Phase 1: use the Watch app.\nCamera and drafts arrive in Phase 3.")
  )
 }
}

/// "Ask with Camera" (spec 19). Phase 1: only opens the app; the camera screen comes in Phase 3.
/// Its purpose now is to confirm it appears in Settings > Action Button > Shortcut (check V5).
struct AskWithCameraIntent: AppIntent {
 static let title: LocalizedStringResource = "Ask with Camera"
 static let description = IntentDescription("Opens the AI Copilot camera to photograph pages.")
 static let openAppWhenRun = true

 func perform() async throws -> some IntentResult {
  .result()
 }
}

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

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

/// Registers "Ask with Camera" as an App Shortcut (Siri, Spotlight, Shortcuts app).
/// The intent itself lives in iOSShared/AskWithCameraIntent.swift. The Action Button route is the
/// Control in iOSWidgets (more reliable, see docs PI 2.4).
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

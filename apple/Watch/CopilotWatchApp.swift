import CopilotCore
import SwiftUI
import WatchKit

/// Entry point of the watchOS app and its composition root: the only place that decides
/// which concrete implementations are used (Dependency Inversion - everything else sees protocols).
///
/// Swift notes:
/// - `@main` marks the program entry point (like `public static void main`).
/// - `App` / `Scene` / `View` are SwiftUI protocols; `body` describes the UI declaratively and is
///  re-evaluated whenever observed state changes.
@main
struct CopilotWatchApp: App {
 /// `@State` keeps the store alive for the whole app lifetime (SwiftUI owns the storage).
 @State private var store = WatchStore(
  // Real backend when configured, otherwise the in-process mock (see AppConfiguration).
  service: AppConfiguration.makeService(),
  // Subtle haptic when an answer is ready (spec 39). No sound, no speech.
  onAnswerReady: { WKInterfaceDevice.current().play(.notification) }
 )

 var body: some Scene {
  WindowGroup {
   RootView()
    // Makes the store available to every view below via `@Environment(WatchStore.self)`
    // (a lightweight dependency injection built into SwiftUI).
    .environment(store)
    // App-wide accent color for primary actions.
    .tint(CompactStyle.accent)
    // No autocorrection in any text input of the app: it rewrites Danish words typed on purpose
    // (owner's request). An environment value, so every TextFieldLink below inherits it.
    .autocorrectionDisabled(true)
  }
 }
}

/// Navigation container + refresh on activation.
struct RootView: View {
 @Environment(WatchStore.self) private var store
 /// The scene phase changes to `.active` when the user raises the wrist or opens the app.
 @Environment(\.scenePhase) private var scenePhase

 var body: some View {
  // `@Bindable` lets us create two-way bindings (`$store.path`) to an @Observable object.
  @Bindable var store = store
  NavigationStack(path: $store.path) {
   HomeView()
    .navigationDestination(for: WatchRoute.self) { route in
     switch route {
     case .conversation: ConversationView()
     case .history: HistoryView()
     case .inputLab: InputLabView()
     }
    }
  }
  // `.task` runs async work when the view appears and cancels it when the view disappears.
  .task {
   await store.refresh()
   if LaunchOptions.demoConversation { store.path = [.conversation] }
  }
  .onChange(of: scenePhase) { _, phase in
   if phase == .active {
    Task { await store.refresh() }
   }
  }
  // Foreground-only polling while photos are uploading from the iPhone, so "Uploading 1/3…"
  // turns into "3 photos ready" without user action. `.task(id:)` restarts when the scene phase
  // changes and is cancelled automatically, so nothing runs while the app is in the background.
  .task(id: scenePhase) {
   guard scenePhase == .active else { return }
   while !Task.isCancelled {
    try? await Task.sleep(for: .seconds(3))
    if store.needsPeriodicRefresh {
     await store.refresh()
    }
   }
  }
 }
}

/// Debug-only launch arguments (e.g. `xcrun simctl launch <sim> <bundle id> -demoConversation`).
/// In Release builds every option is `false`, so they cannot affect the real app.
enum LaunchOptions {
 /// Starts on the conversation screen with demo messages, to review its layout in the simulator.
 static var demoConversation: Bool {
  #if DEBUG
  CommandLine.arguments.contains("-demoConversation")
  #else
  false
  #endif
 }
}

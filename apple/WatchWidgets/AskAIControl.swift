import AppIntents
import SwiftUI
import WidgetKit

/// Entry point of the Watch widget extension: the Action Button Control and the complication (spec 40).
@main
struct CopilotWatchWidgets: WidgetBundle {
 var body: some Widget {
  AskAIControl()
  CopilotComplication()
 }
}

/// "Ask AI" Control (watchOS 26+).
///
/// Controls can be placed in Control Center, the Smart Stack and **assigned to the Action button on
/// Apple Watch Ultra** (WWDC25 "What's new in watchOS 26"). This is the supported way to put our app
/// on the Ultra Action Button without workout/dive APIs (spec 41).
///
/// Setup on the watch: Settings > Action Button > Controls (or the equivalent entry) > AI Copilot > Ask AI.
struct AskAIControl: ControlWidget {
 /// Stable identifier of this control. Changing it would remove the control from users' setups.
 static let kind = "AskAIControl"

 var body: some ControlWidgetConfiguration {
  // "Static" = the control has no user-configurable parameters.
  StaticControlConfiguration(kind: Self.kind) {
   // A button that runs AskAIIntent, which opens the Watch app.
   ControlWidgetButton(action: AskAIIntent()) {
    Label("Ask AI", systemImage: "sparkles")
   }
  }
  .displayName("Ask AI")
  .description("Open AI Copilot to ask a question.")
 }
}

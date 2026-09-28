import AppIntents
import SwiftUI
import WidgetKit

/// Entry point of the iOS widget extension. For now it contains only one Control.
@main
struct CopilotWidgets: WidgetBundle {
 var body: some Widget {
  AskWithCameraControl()
 }
}

/// "Ask with Camera" Control (iOS 18+).
///
/// Controls can be placed in Control Center, on the Lock Screen and **assigned directly to the
/// iPhone Action Button** (Settings > Action Button > Controls). This does not depend on the
/// App Shortcuts index, which did not list our app on the owner's iPhone (see docs, PI 2.4).
/// Later the same Control can launch a Lock Screen capture extension (PI 3, Phase 6).
struct AskWithCameraControl: ControlWidget {
 /// Stable identifier of this control. Changing it would remove the control from users' setups.
 static let kind = "AskWithCameraControl"

 var body: some ControlWidgetConfiguration {
  StaticControlConfiguration(kind: Self.kind) {
   ControlWidgetButton(action: AskWithCameraIntent()) {
    Label("Ask with Camera", systemImage: "camera.viewfinder")
   }
  }
  .displayName("Ask with Camera")
  .description("Photograph pages for AI Copilot.")
 }
}

import CopilotCore
import SwiftUI
import WidgetKit

/// Watch face complication and Smart Stack widget (spec 40): "📷 2/3" while photos upload,
/// "AI" with a running timer while the AI works, "AI ✓" when the answer is ready.
///
/// Where the data comes from: the extension asks the backend itself (`GET /v1/home`, one small call),
/// with the same build-time configuration as the app. No App Group / shared storage is needed (KISS),
/// which also avoids a capability that free signing may not support.
///
/// When it refreshes (honest limits, no push on a free account):
/// - immediately whenever the Watch app is open and the state changes (the app calls `reloadAllTimelines`);
/// - otherwise when watchOS grants a timeline reload: we ask for one in 5 minutes while something is in
///  progress and in 30 minutes when idle, but the system decides (daily budget).
/// The processing timer counts on the watch face by itself (`Text(date, style: .timer)`), no reload needed.
struct CopilotComplication: Widget {
 static let kind = "CopilotComplication"

 var body: some WidgetConfiguration {
  StaticConfiguration(kind: Self.kind, provider: GlanceProvider()) { entry in
   GlanceView(entry: entry)
    // Required by watchOS 10+ for accessory widgets; the system draws its own background.
    .containerBackground(.fill.tertiary, for: .widget)
  }
  .configurationDisplayName("AI Copilot")
  .description("Photo uploads, AI progress and answers.")
  .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
 }
}

struct GlanceEntry: TimelineEntry {
 let date: Date
 let state: GlanceState
 /// False when the backend could not be reached: the view shows the last known look without claiming progress.
 let isLive: Bool
}

struct GlanceProvider: TimelineProvider {

 func placeholder(in context: Context) -> GlanceEntry {
  GlanceEntry(date: Date(), state: .idle, isLive: true)
 }

 func getSnapshot(in context: Context, completion: @escaping @Sendable (GlanceEntry) -> Void) {
  // The watch face gallery: an example that shows what the complication is for.
  if context.isPreview {
   completion(GlanceEntry(date: Date(), state: .answerReady(sentAt: Date()), isLive: true))
   return
  }
  Task { completion(await Self.currentEntry()) }
 }

 func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<GlanceEntry>) -> Void) {
  Task {
   let entry = await Self.currentEntry()
   var entries = [entry]
   // "Answer ready" fades to idle by itself after a while: schedule that moment.
   if let expiry = entry.state.expiresAt {
    entries.append(GlanceEntry(date: expiry, state: .idle, isLive: entry.isLive))
   }
   let refresh = entry.state.isInProgress || !entry.isLive ? 5 : 30
   completion(Timeline(entries: entries, policy: .after(Date().addingTimeInterval(TimeInterval(refresh * 60)))))
  }
 }

 private static func currentEntry() async -> GlanceEntry {
  guard let configuration = BackendConfiguration.fromInfoPlist() else {
   return GlanceEntry(date: Date(), state: .idle, isLive: false)
  }
  let service = LiveCopilotService(baseURL: configuration.baseURL, deviceToken: configuration.deviceToken)
  do {
   let home = try await service.home()
   return GlanceEntry(date: Date(), state: GlanceState(home: home), isLive: true)
  } catch {
   return GlanceEntry(date: Date(), state: .idle, isLive: false)
  }
 }
}

/// One view for all families; each family gets the amount of text it has room for.
struct GlanceView: View {
 @Environment(\.widgetFamily) private var family
 let entry: GlanceEntry

 var body: some View {
  switch family {
  case .accessoryRectangular: rectangular
  case .accessoryInline: Text(inlineText)
  case .accessoryCorner:
   Image(systemName: symbol)
    .font(.title3)
    .widgetLabel { Text(inlineText) }
  default: circular
  }
 }

 /// Icon + one short value, e.g. camera + "2/3" or sparkles + timer.
 private var circular: some View {
  ZStack {
   AccessoryWidgetBackground()
   VStack(spacing: 0) {
    Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
    shortValue
     .font(.system(size: 12, weight: .medium))
     .minimumScaleFactor(0.6)
     .lineLimit(1)
   }
   .padding(4)
  }
 }

 private var rectangular: some View {
  VStack(alignment: .leading, spacing: 2) {
   Label("AI Copilot", systemImage: symbol)
    .font(.headline)
    .widgetAccentable()
   detail.font(.body).lineLimit(2)
  }
  .frame(maxWidth: .infinity, alignment: .leading)
 }

 @ViewBuilder
 private var shortValue: some View {
  switch entry.state {
  case .idle: Text("AI")
  case .uploading(let uploaded, let total): Text("\(uploaded)/\(total)")
  case .photosReady(let count): Text("\(count)")
  case .needsAttention: Text("!")
  // Counts up on the watch face by itself.
  case .processing(let since): Text(since, style: .timer).multilineTextAlignment(.center)
  case .answerReady: Text("✓")
  case .failed: Text("✕")
  }
 }

 @ViewBuilder
 private var detail: some View {
  switch entry.state {
  case .idle: Text(entry.isLive ? "Ready" : "Offline")
  case .uploading(let uploaded, let total): Text("Uploading \(uploaded)/\(total) photos")
  case .photosReady(let count): Text(count == 1 ? "1 photo ready - Send" : "\(count) photos ready - Send")
  case .needsAttention: Text("A photo failed - fix on iPhone")
  case .processing(let since): Text("Thinking… \(Text(since, style: .timer))")
  case .answerReady: Text("Answer ready")
  case .failed: Text("No answer - ask again")
  }
 }

 private var inlineText: String {
  switch entry.state {
  case .idle: "AI"
  case .uploading(let uploaded, let total): "📷 \(uploaded)/\(total)"
  case .photosReady(let count): "📷 \(count) ready"
  case .needsAttention: "📷 failed"
  case .processing: "AI …"
  case .answerReady: "AI ✓"
  case .failed: "AI ✕"
  }
 }

 private var symbol: String {
  switch entry.state {
  case .idle: "sparkles"
  case .uploading, .photosReady: "camera.fill"
  case .needsAttention: "exclamationmark.triangle.fill"
  case .processing: "hourglass"
  case .answerReady: "checkmark.bubble.fill"
  case .failed: "xmark.octagon.fill"
  }
 }
}

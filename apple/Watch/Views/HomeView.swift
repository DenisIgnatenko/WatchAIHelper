import CopilotCore
import SwiftUI

/// Main screen (spec 13): Ask, current draft, status, latest answer, history.
/// Designed for the minimum number of taps: Ask is one tap to the system text input.
struct HomeView: View {
 @Environment(WatchStore.self) private var store

 var body: some View {
  List {
   if let home = store.home {
    // Draft card only when the iPhone has put photos into the draft (spec 30).
    if home.draft.totalAttachments > 0 {
     DraftCard(draft: home.draft)
    }

    // `TextFieldLink` is a button that opens the native watchOS text input
    // (dictation / keyboard - spec 14) and calls the closure with the result.
    // With photos in the draft the text joins them (decision Q1).
    TextFieldLink(prompt: Text(home.draft.totalAttachments > 0 ? "Question about the photos" : "Your question")) {
     Label("Ask", systemImage: "mic.fill")
    } onSubmit: { text in
     Task { await store.send(text: text) }
    }
    .compactRow()

    if let request = store.activeRequest, !request.state.isTerminal {
     StatusRow(text: request.state.statusText)
    }

    if let unsent = store.unsentText {
     Text("Not sent: \(unsent)")
      .foregroundStyle(.secondary)
      .infoRow()
     Button("Retry") { Task { await store.send(text: unsent) } }
      .compactRow()
    }

    if let answer = home.lastAnswer {
     NavigationLink(value: WatchRoute.conversation) {
      // Answer preview keeps the regular font: reading answers is the main job of the Watch.
      Text(answer.text ?? "")
       .font(.body)
       .lineLimit(4)
     }
     .compactRow()
    }

    NavigationLink(value: WatchRoute.history) {
     Label(home.activeConversation.title, systemImage: "bubble.left.and.bubble.right")
    }
    .compactRow()
    NavigationLink(value: WatchRoute.inputLab) {
     Label("Input test", systemImage: "character.cursor.ibeam")
    }
    .compactRow()
   } else if let error = store.errorText {
    Text(error).infoRow()
    Button("Retry") { Task { await store.refresh() } }
   } else {
    ProgressView()
   }
  }
  .compactList()
  .navigationTitle("AI Copilot")
  // Pull down to refresh, like on iPhone.
  .refreshable { await store.refresh() }
 }
}

/// Spinner + short status, shown as plain information (not a button).
struct StatusRow: View {
 let text: String

 var body: some View {
  HStack(spacing: 6) {
   ProgressView().frame(width: 16, height: 16)
   Text(text).foregroundStyle(.secondary)
  }
  .infoRow()
 }
}

/// "3 photos ready ✓" + one row with [Send] [Text].
private struct DraftCard: View {
 @Environment(WatchStore.self) private var store
 let draft: DraftSummary

 var body: some View {
  let readiness = draft.readiness
  Label(readiness.statusText, systemImage: icon(for: readiness))
   .foregroundStyle(isFailed(readiness) ? .red : .primary)
   .infoRow()

  if isFailed(readiness) {
   // Invariant 6: never analyse an incomplete set. Fixing happens on the iPhone (Retry / Remove).
   Text("Fix on iPhone").foregroundStyle(.secondary).infoRow()
  } else {
   // Two actions side by side instead of two full-width rows: half the height.
   // `.bordered` gives each button its own tap area inside the shared row.
   HStack(spacing: 6) {
    // Allowed while uploading: the backend waits for the remaining photos (architecture option B).
    // Prominent (filled) style marks Send as the primary action.
    Button {
     Task { await store.send(text: nil) }
    } label: {
     Label("Send", systemImage: "paperplane.fill")
    }
    .buttonStyle(.borderedProminent)
    TextFieldLink(prompt: Text("Add a question")) {
     Label("Text", systemImage: "text.bubble")
    } onSubmit: { text in
     Task { await store.send(text: text) }
    }
    .buttonStyle(.bordered)
   }
   .controlSize(CompactStyle.inlineButtonSize)
   .infoRow()
  }
 }

 private func icon(for readiness: DraftSummary.Readiness) -> String {
  switch readiness {
  case .ready: "checkmark.circle.fill"
  case .uploading: "arrow.up.circle"
  case .hasFailures: "exclamationmark.triangle.fill"
  case .noAttachments: "photo"
  }
 }

 private func isFailed(_ readiness: DraftSummary.Readiness) -> Bool {
  if case .hasFailures = readiness { return true }
  return false
 }
}

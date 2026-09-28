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
     Section("Current draft") {
      DraftCard(draft: home.draft)
     }
    }

    Section {
     // `TextFieldLink` is a button that opens the native watchOS text input
     // (dictation / keyboard / Scribble - spec 14) and calls the closure with the result.
     // With photos in the draft the text joins them (decision Q1).
     TextFieldLink(prompt: Text(home.draft.totalAttachments > 0 ? "Question about the photos" : "Your question")) {
      Label("Ask", systemImage: "mic.fill")
     } onSubmit: { text in
      Task { await store.send(text: text) }
     }

     if let request = store.activeRequest, !request.state.isTerminal {
      HStack {
       ProgressView().frame(width: 20)
       Text(request.state.statusText)
      }
     }
    }

    if let unsent = store.unsentText {
     Section("Not sent") {
      Text(unsent).foregroundStyle(.secondary)
      Button("Retry") { Task { await store.send(text: unsent) } }
     }
    }

    if let answer = home.lastAnswer {
     Section("Last answer") {
      NavigationLink(value: WatchRoute.conversation) {
       Text(answer.text ?? "")
        .lineLimit(4)
      }
     }
    }

    Section {
     NavigationLink(value: WatchRoute.history) {
      Label(home.activeConversation.title, systemImage: "bubble.left.and.bubble.right")
     }
     NavigationLink(value: WatchRoute.inputLab) {
      Label("Input test", systemImage: "character.cursor.ibeam")
     }
    }
   } else if let error = store.errorText {
    Text(error)
    Button("Retry") { Task { await store.refresh() } }
   } else {
    ProgressView()
   }
  }
  .navigationTitle("AI Copilot")
  // Pull down to refresh, like on iPhone.
  .refreshable { await store.refresh() }
 }
}

/// "3 photos ready ✓  [Send] [Add text & Send]".
private struct DraftCard: View {
 @Environment(WatchStore.self) private var store
 let draft: DraftSummary

 var body: some View {
  let readiness = draft.readiness
  Label(readiness.statusText, systemImage: icon(for: readiness))
   .foregroundStyle(isFailed(readiness) ? .red : .primary)

  if isFailed(readiness) {
   // Invariant 6: never analyse an incomplete set. Fixing happens on the iPhone (Retry / Remove).
   Text("Fix on iPhone").font(.footnote).foregroundStyle(.secondary)
  } else {
   // Allowed while uploading: the backend waits for the remaining photos (architecture option B).
   Button {
    Task { await store.send(text: nil) }
   } label: {
    Label("Send", systemImage: "paperplane.fill")
   }
   TextFieldLink(prompt: Text("Add a question")) {
    Label("Add text & Send", systemImage: "text.bubble")
   } onSubmit: { text in
    Task { await store.send(text: text) }
   }
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

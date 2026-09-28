import CopilotCore
import SwiftUI

/// The active conversation: messages, processing state, suggested follow-ups, Ask.
/// Scrolling with the Digital Crown works out of the box for `ScrollView` on watchOS (spec 15).
struct ConversationView: View {
 @Environment(WatchStore.self) private var store
 /// Invisible anchor at the bottom, used to auto-scroll to the newest content.
 private let bottomAnchor = "bottom"

 var body: some View {
  // `ScrollViewReader` gives a proxy that can scroll programmatically to a view with a given id.
  ScrollViewReader { proxy in
   ScrollView {
    LazyVStack(alignment: .leading, spacing: 8) {
     ForEach(store.messages) { message in
      MessageRow(message: message)
     }

     if let request = store.activeRequest, !request.state.isTerminal {
      HStack(spacing: 6) {
       ProgressView().frame(width: 16, height: 16)
       Text(request.state.statusText).foregroundStyle(.secondary)
      }
      .font(CompactStyle.controlFont)
     }

     // Controls are compact; the answer text above keeps the regular font (readability first).
     VStack(spacing: 4) {
      // Follow-ups only under the latest answer (spec 16, max three).
      if let last = store.messages.last, last.role == .assistant, store.activeRequest?.state.isTerminal ?? true {
       ForEach(last.suggestedActions.prefix(3), id: \.self) { action in
        Button(action.title) {
         Task { await store.send(text: action.prompt) }
        }
       }
      }

      TextFieldLink(prompt: Text("Follow-up question")) {
       Label("Ask", systemImage: "mic.fill")
      } onSubmit: { text in
       Task { await store.send(text: text) }
      }
      .id(bottomAnchor)
     }
     .buttonStyle(.bordered)
     .controlSize(.small)
     .font(CompactStyle.controlFont)
    }
   }
   .onAppear { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
   // When a new message arrives, jump to it. (The user can scroll back with the Crown.)
   .onChange(of: store.messages.count) {
    withAnimation { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
   }
  }
  .navigationTitle(store.home?.activeConversation.title ?? "")
 }
}

private struct MessageRow: View {
 let message: Message

 var body: some View {
  VStack(alignment: .leading, spacing: 4) {
   if message.attachmentCount > 0 {
    Label(message.attachmentCount == 1 ? "1 photo" : "\(message.attachmentCount) photos", systemImage: "photo.on.rectangle")
     .font(.footnote)
   }
   if let text = message.text {
    Text(text)
   }
  }
  .padding(8)
  // User messages get a tinted background; answers are plain text for maximum readability.
  .background(message.role == .user ? Color.accentColor.opacity(0.25) : .clear, in: .rect(cornerRadius: 10))
  .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
 }
}

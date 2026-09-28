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

     // Follow-ups only under the latest answer (spec 16, max three).
     if let last = store.messages.last, last.role == .assistant, store.activeRequest?.state.isTerminal ?? true {
      let actions = Array(last.suggestedActions.prefix(3))
      // `ViewThatFits` picks the first layout that fits the width: one row if the titles are short,
      // otherwise a column. No manual text measuring.
      ViewThatFits(in: .horizontal) {
       HStack(spacing: 4) { suggestionButtons(actions) }
       VStack(spacing: 4) { suggestionButtons(actions) }
      }
     }

     TextFieldLink(prompt: Text("Follow-up question")) {
      Label("Ask", systemImage: "mic.fill")
       .frame(maxWidth: .infinity)
     } onSubmit: { text in
      Task { await store.send(text: text) }
     }
     .buttonStyle(.borderedProminent)
     .id(bottomAnchor)
    }
    .controlSize(CompactStyle.inlineButtonSize)
    .font(CompactStyle.controlFont)
   }
   // Open the conversation at its end (the newest answer).
   .defaultScrollAnchor(.bottom)
   // When a new message arrives, jump to it. (The user can scroll back with the Crown.)
   .onChange(of: store.messages.count) {
    withAnimation { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
   }
  }
  .navigationTitle(store.home?.activeConversation.title ?? "")
 }
}

extension ConversationView {
 /// Buttons for suggested follow-ups. A function (not a stored view) so both layouts
 /// inside `ViewThatFits` build their own copies.
 @ViewBuilder
 private func suggestionButtons(_ actions: [SuggestedAction]) -> some View {
  ForEach(actions, id: \.self) { action in
   Button(action.title) {
    Task { await store.send(text: action.prompt) }
   }
   .buttonStyle(.bordered)
  }
 }
}

private struct MessageRow: View {
 let message: Message

 var body: some View {
  VStack(alignment: .leading, spacing: 4) {
   if message.attachmentCount > 0 {
    Label(message.attachmentCount == 1 ? "1 photo" : "\(message.attachmentCount) photos", systemImage: "photo.on.rectangle")
     .font(.caption2)
    .foregroundStyle(.secondary)
   }
   if let text = message.text {
    Text(text).font(CompactStyle.messageFont)
   }
  }
  .padding(message.role == .user ? 6 : 2)
  // User messages get a tinted background; answers are plain text for maximum readability.
  .background(message.role == .user ? CompactStyle.accent.opacity(0.3) : .clear, in: .rect(cornerRadius: 8))
  .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
 }
}

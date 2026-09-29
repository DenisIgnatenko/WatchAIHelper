import CopilotCore
import SwiftUI

/// All messages of one conversation, oldest first, opened at the newest one.
/// Read-only: questions are asked from the draft screen or the Watch.
struct ConversationHistoryView: View {
 @Environment(DraftStore.self) private var store
 let conversation: Conversation
 @State private var messages: [Message] = []
 @State private var errorText: String?
 @State private var isLoading = true

 var body: some View {
  ScrollView {
   LazyVStack(alignment: .leading, spacing: 12) {
    ForEach(messages) { message in
     MessageBubble(message: message)
    }
    if let errorText {
     Text(errorText).foregroundStyle(.red).font(.footnote)
    } else if messages.isEmpty && !isLoading {
     ContentUnavailableView("No messages yet", systemImage: "text.bubble")
    }
   }
   .padding()
  }
  .defaultScrollAnchor(.bottom)
  .overlay { if isLoading && messages.isEmpty { ProgressView() } }
  .navigationTitle(conversation.title)
  .navigationBarTitleDisplayMode(.inline)
  .task { await load() }
  .refreshable { await load() }
 }

 private func load() async {
  do {
   messages = try await store.service.messages(conversationId: conversation.id)
   errorText = nil
  } catch {
   errorText = "Could not load the messages."
  }
  isLoading = false
 }
}

/// Questions on the right in a tinted bubble, answers on the left as plain, selectable text.
private struct MessageBubble: View {
 let message: Message

 var body: some View {
  let isUser = message.role == .user
  VStack(alignment: .leading, spacing: 6) {
   if message.attachmentCount > 0 {
    Label(message.attachmentCount == 1 ? "1 photo" : "\(message.attachmentCount) photos", systemImage: "photo.on.rectangle")
     .font(.caption)
     .foregroundStyle(.secondary)
   }
   if let text = message.text {
    Text(text).textSelection(.enabled)
   }
   Text(message.createdAt, format: .dateTime.day().month().hour().minute())
    .font(.caption2)
    .foregroundStyle(.tertiary)
  }
  .padding(isUser ? 10 : 2)
  .background(isUser ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 12))
  .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
  .padding(isUser ? .leading : .trailing, 40)
 }
}

import CopilotCore
import SwiftUI

/// All conversations: choose the active one (it receives photos and questions on the iPhone AND the Watch),
/// start a new one, rename, delete, or read its messages.
///
/// Gestures follow iOS conventions: tap = choose, swipe left = delete / rename, long press = menu.
struct ConversationsView: View {
 @Environment(DraftStore.self) private var store
 @Environment(\.dismiss) private var dismiss
 /// Conversation waiting for the delete confirmation (deleting is irreversible).
 @State private var pendingDeletion: Conversation?
 /// Conversation being renamed, and the text field value.
 @State private var renaming: Conversation?
 @State private var newTitle = ""

 var body: some View {
  List {
   ForEach(store.conversations) { conversation in
    Button {
     Task {
      await store.select(conversation)
      dismiss()
     }
    } label: {
     ConversationRow(conversation: conversation, isActive: conversation.id == store.conversation?.id)
    }
    .swipeActions(edge: .trailing) {
     Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = conversation }
     Button("Rename", systemImage: "pencil") { startRenaming(conversation) }
      .tint(.orange)
    }
    .contextMenu {
     NavigationLink {
      ConversationHistoryView(conversation: conversation)
     } label: {
      Label("Show messages", systemImage: "text.bubble")
     }
     Button("Rename", systemImage: "pencil") { startRenaming(conversation) }
     Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = conversation }
    }
   }
  }
  .navigationTitle("Conversations")
  .toolbar {
   ToolbarItem(placement: .topBarTrailing) {
    Menu {
     ForEach(ConversationMode.allCases, id: \.self) { mode in
      Button(mode.displayName, systemImage: mode.symbolName) {
       Task {
        await store.newConversation(mode: mode)
        dismiss()
       }
      }
     }
    } label: {
     Label("New conversation", systemImage: "plus")
    }
   }
  }
  .task { await store.loadConversations() }
  .refreshable { await store.loadConversations() }
  .alert("Rename conversation", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
   TextField("Title", text: $newTitle)
   Button("Save") {
    if let conversation = renaming {
     Task { await store.rename(conversation, to: newTitle) }
    }
    renaming = nil
   }
   Button("Cancel", role: .cancel) { renaming = nil }
  } message: {
   Text("Your title is kept: the AI will not change it.")
  }
  .confirmationDialog(
   "Delete \"\(pendingDeletion?.title ?? "")\"?",
   isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
   titleVisibility: .visible
  ) {
   Button("Delete", role: .destructive) {
    if let conversation = pendingDeletion {
     Task { await store.delete(conversation) }
    }
    pendingDeletion = nil
   }
  } message: {
   Text("Messages and photos are deleted from the server. This cannot be undone.")
  }
 }

 private func startRenaming(_ conversation: Conversation) {
  newTitle = conversation.title
  renaming = conversation
 }
}

private struct ConversationRow: View {
 let conversation: Conversation
 let isActive: Bool

 var body: some View {
  HStack(spacing: 12) {
   Image(systemName: conversation.mode.symbolName)
    .foregroundStyle(.tint)
    .frame(width: 28)
   VStack(alignment: .leading, spacing: 2) {
    Text(conversation.title).foregroundStyle(.primary).lineLimit(2)
    Text(conversation.updatedAt, style: .relative)
     .font(.caption)
     .foregroundStyle(.secondary)
   }
   Spacer()
   if isActive {
    Image(systemName: "checkmark").foregroundStyle(.tint)
   }
  }
 }
}

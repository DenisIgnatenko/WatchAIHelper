import CopilotCore
import SwiftUI

/// Conversation history: pick the active conversation or start a new one.
struct HistoryView: View {
 @Environment(WatchStore.self) private var store

 var body: some View {
  List {
   Button {
    Task { await store.createConversation() }
   } label: {
    Label("New conversation", systemImage: "plus")
   }

   ForEach(store.conversations) { conversation in
    Button {
     Task { await store.selectConversation(conversation) }
    } label: {
     VStack(alignment: .leading) {
      Text(conversation.title)
      Text(conversation.updatedAt, style: .relative)
       .font(.footnote)
       .foregroundStyle(.secondary)
     }
    }
   }

   // Phase 1 only: lets us try the draft card states without an iPhone app.
   Section("Mock (Phase 1)") {
    Button("Draft: 3 photos uploading") { Task { await store.resetMock(scenario: .photosUploading(3)) } }
    Button("Draft: 3 photos ready") { Task { await store.resetMock(scenario: .photosReady(3)) } }
    Button("Draft: empty") { Task { await store.resetMock(scenario: .empty) } }
   }
  }
  .navigationTitle("History")
  .task { await store.loadConversations() }
 }
}

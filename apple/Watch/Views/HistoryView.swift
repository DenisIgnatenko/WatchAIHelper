import CopilotCore
import SwiftUI

/// Conversation history: pick the active conversation or start a new one.
struct HistoryView: View {
 @Environment(WatchStore.self) private var store

 var body: some View {
  List {
   // New conversation of each type; "Danish exam" adds the exam guide and study materials.
   ForEach(ConversationMode.allCases, id: \.self) { mode in
    Button {
     Task { await store.createConversation(mode: mode) }
    } label: {
     Label("New: \(mode.displayName)", systemImage: "plus")
    }
   }

   ForEach(store.conversations) { conversation in
    Button {
     Task { await store.selectConversation(conversation) }
    } label: {
     VStack(alignment: .leading) {
      Label(conversation.title, systemImage: conversation.mode.symbolName)
      Text(conversation.updatedAt, style: .relative)
       .font(.footnote)
       .foregroundStyle(.secondary)
     }
    }
   }

   // Only without a backend: lets us try the draft card states without an iPhone app.
   if store.isUsingMock {
    Section("Mock") {
     Button("Draft: 3 photos uploading") { Task { await store.resetMock(scenario: .photosUploading(3)) } }
     Button("Draft: 3 photos ready") { Task { await store.resetMock(scenario: .photosReady(3)) } }
     Button("Draft: empty") { Task { await store.resetMock(scenario: .empty) } }
    }
   }
  }
  .compactList()
  .navigationTitle("History")
  .task { await store.loadConversations() }
 }
}

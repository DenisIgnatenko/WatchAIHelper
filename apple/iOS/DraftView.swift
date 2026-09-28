import CopilotCore
import SwiftUI

/// iPhone main screen = the current draft of the active conversation (spec 23):
/// photos with upload state, [Camera], optional question, [Send], request status and the latest answer.
struct DraftView: View {
 @Environment(DraftStore.self) private var store
 @Binding var showCamera: Bool

 private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

 var body: some View {
  // `@Bindable` gives two-way bindings ($store.text) to an @Observable object.
  @Bindable var store = store
  NavigationStack {
   ScrollView {
    VStack(alignment: .leading, spacing: 16) {
     if !store.tiles.isEmpty {
      LazyVGrid(columns: columns, spacing: 8) {
       ForEach(store.tiles) { tile in
        TileView(tile: tile)
         // Long-press menu: Retry / Remove (spec 23, 26).
         .contextMenu {
          if case .failed = tile.phase {
           Button("Retry upload", systemImage: "arrow.clockwise") { store.retry(tile.id) }
          }
          Button("Remove", systemImage: "trash", role: .destructive) {
           Task { await store.remove(tile.id) }
          }
         }
       }
      }
     }

     Button {
      showCamera = true
     } label: {
      Label(store.tiles.isEmpty ? "Take photo" : "Add photo", systemImage: "camera.fill")
       .frame(maxWidth: .infinity)
     }
     .buttonStyle(.bordered)
     .controlSize(.large)

     TextField("Question (optional)", text: $store.text, axis: .vertical)
      .textFieldStyle(.roundedBorder)
      .lineLimit(1...4)

     Button {
      Task { await store.send() }
     } label: {
      Label("Send", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
     }
     .buttonStyle(.borderedProminent)
     .controlSize(.large)
     .disabled(!store.canSend)

     if let request = store.request, !request.state.isTerminal {
      HStack {
       ProgressView()
       Text(statusText(request.state)).foregroundStyle(.secondary)
      }
     }
     if let error = store.errorText {
      Text(error).foregroundStyle(.red).font(.footnote)
     }

     if let answer = store.lastAnswer?.text {
      VStack(alignment: .leading, spacing: 6) {
       Text("Last answer").font(.caption).foregroundStyle(.secondary)
       Text(answer)
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.fill.tertiary, in: .rect(cornerRadius: 12))
     }
    }
    .padding()
   }
   .navigationTitle(store.conversation?.title ?? "AI Copilot")
   .navigationBarTitleDisplayMode(.inline)
   .toolbar {
    // Which conversation receives the photos and the answer - always visible and switchable.
    ToolbarItem(placement: .topBarTrailing) { ConversationMenu() }
   }
   .refreshable { await store.refresh() }
  }
 }

 private func statusText(_ state: AIRequest.State) -> String {
  switch state {
  case .waitingForAttachments(let uploaded, let total): "Waiting for photos \(uploaded)/\(total)…"
  case .blocked: "A photo failed. Retry or remove it."
  case .queued, .processing: "Processing… you can put the iPhone away."
  case .completed: "Answer ready"
  case .failed(let reason): reason
  case .cancelled: "Cancelled"
  }
 }
}

/// Conversation picker: the checked one is active on the iPhone AND the Watch (stored on the backend).
private struct ConversationMenu: View {
 @Environment(DraftStore.self) private var store

 var body: some View {
  Menu {
   Button("New conversation", systemImage: "plus") {
    Task { await store.newConversation() }
   }
   Section("Conversations") {
    ForEach(store.conversations) { conversation in
     Button {
      Task { await store.select(conversation) }
     } label: {
      if conversation.id == store.conversation?.id {
       Label(conversation.title, systemImage: "checkmark")
      } else {
       Text(conversation.title)
      }
     }
    }
   }
  } label: {
   Image(systemName: "bubble.left.and.bubble.right")
  }
  // Load the list when the menu button appears (and again after each switch).
  .task { await store.loadConversations() }
 }
}

/// One photo tile with its upload state badge.
private struct TileView: View {
 let tile: DraftStore.Tile

 var body: some View {
  ZStack(alignment: .bottomTrailing) {
   Group {
    if let thumbnail = tile.thumbnail {
     Image(decorative: thumbnail, scale: 1).resizable().scaledToFill()
    } else {
     // Uploaded from another session: no local preview, only the fact that the page exists.
     Image(systemName: "doc.text.image").font(.largeTitle).foregroundStyle(.secondary)
    }
   }
   .frame(width: 96, height: 128)
   .clipShape(.rect(cornerRadius: 8))
   .background(.fill.tertiary, in: .rect(cornerRadius: 8))

   badge.padding(4)
  }
 }

 @ViewBuilder
 private var badge: some View {
  switch tile.phase {
  case .preparing:
   ProgressView().controlSize(.small).padding(4).background(.thinMaterial, in: .circle)
  case .uploading(let fraction):
   ProgressView(value: fraction).progressViewStyle(.circular).controlSize(.small)
    .padding(4).background(.thinMaterial, in: .circle)
  case .uploaded:
   Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, .green)
  case .failed:
   Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.white, .red)
  }
 }
}

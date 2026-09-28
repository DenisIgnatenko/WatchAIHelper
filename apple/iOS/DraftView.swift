import CopilotCore
import PhotosUI
import SwiftUI

/// iPhone main screen = the current draft of the active conversation (spec 23):
/// photos with upload state, [Camera], optional question, [Send], request status and the latest answer.
struct DraftView: View {
 @Environment(DraftStore.self) private var store
 @Binding var showCamera: Bool
 /// Items chosen in the system photo picker; converted into draft images, then cleared.
 @State private var pickedItems: [PhotosPickerItem] = []

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

     HStack {
      Button {
       showCamera = true
      } label: {
       Label(store.tiles.isEmpty ? "Take photo" : "Add photo", systemImage: "camera.fill")
        .frame(maxWidth: .infinity)
      }
      // Photo Library (spec 21): several images at once, numbered in the order you tap them
      // (`.ordered`), which becomes the page order. Picking never starts AI inference.
      PhotosPicker(selection: $pickedItems, maxSelectionCount: 10, selectionBehavior: .ordered, matching: .images) {
       Label("Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
      }
     }
     .buttonStyle(.bordered)
     .controlSize(.large)
     .onChange(of: pickedItems) { _, items in
      guard !items.isEmpty else { return }
      Task { await addPicked(items) }
     }

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
   .navigationTitle(store.conversation.map { $0.mode == .danishExam ? "🎓 \($0.title)" : $0.title } ?? "AI Copilot")
   .navigationBarTitleDisplayMode(.inline)
   .toolbar {
    // Which conversation receives the photos and the answer - always visible and switchable.
    ToolbarItem(placement: .topBarTrailing) { ConversationMenu() }
   }
   .refreshable { await store.refresh() }
  }
 }

 /// Loads the picked images in selection order and adds them to the draft.
 private func addPicked(_ items: [PhotosPickerItem]) async {
  pickedItems = []
  for item in items {
   // Original bytes (HEIC/JPEG); may download from iCloud Photos first.
   if let data = try? await item.loadTransferable(type: Data.self) {
    store.addPhoto(data, source: .photoLibrary)
   }
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
   Section("New conversation") {
    ForEach(ConversationMode.allCases, id: \.self) { mode in
     Button(mode.displayName, systemImage: mode.symbolName) {
      Task { await store.newConversation(mode: mode) }
     }
    }
   }
   Section("Conversations") {
    ForEach(store.conversations) { conversation in
     Button {
      Task { await store.select(conversation) }
     } label: {
      Label(conversation.title, systemImage: conversation.id == store.conversation?.id ? "checkmark" : conversation.mode.symbolName)
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

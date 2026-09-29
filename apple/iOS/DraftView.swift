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
       Label(store.tiles.isEmpty ? "Scan pages" : "Scan more", systemImage: "doc.viewfinder")
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

     if let request = store.visibleRequest {
      RequestStatus(request: request, isLatest: request.id == store.latestRequest?.id)
     }
     if let error = store.errorText {
      Text(error).foregroundStyle(.red).font(.footnote)
     }

     if let conversation = store.conversation {
      // Latest answer; tap for the whole conversation.
      NavigationLink {
       ConversationHistoryView(conversation: conversation)
      } label: {
       VStack(alignment: .leading, spacing: 6) {
        HStack {
         Text(store.lastAnswer == nil ? "Conversation" : "Last answer").font(.caption).foregroundStyle(.secondary)
         Spacer()
         Label("All messages", systemImage: "chevron.right")
          .labelStyle(.titleAndIcon)
          .font(.caption)
          .foregroundStyle(.tint)
        }
        if let answer = store.lastAnswer?.text {
         Text(answer)
          .foregroundStyle(.primary)
          .multilineTextAlignment(.leading)
        }
       }
       .padding()
       .frame(maxWidth: .infinity, alignment: .leading)
       .background(.fill.tertiary, in: .rect(cornerRadius: 12))
      }
      .buttonStyle(.plain)
     }
    }
    .padding()
   }
   .navigationTitle(store.conversation.map { $0.mode == .danishExam ? "🎓 \($0.title)" : $0.title } ?? "AI Copilot")
   .navigationBarTitleDisplayMode(.inline)
   .toolbar {
    ToolbarItem(placement: .topBarLeading) {
     NavigationLink {
      UsageView()
     } label: {
      Label("AI costs", systemImage: "chart.bar")
     }
    }
    // Which conversation receives the photos and the answer - always visible and switchable.
    ToolbarItem(placement: .topBarTrailing) {
     NavigationLink {
      ConversationsView()
     } label: {
      Label("Conversations", systemImage: "bubble.left.and.bubble.right")
     }
    }
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

}

/// State of the Send with the action that fits it (spec 26): Cancel while photos are missing,
/// Ask again after a failed answer. Elapsed time since Send, so a long wait is visible.
private struct RequestStatus: View {
 @Environment(DraftStore.self) private var store
 let request: AIRequest
 /// Retry only makes sense for the latest question of the conversation (the backend enforces it too).
 let isLatest: Bool

 var body: some View {
  if !request.state.isTerminal {
   VStack(alignment: .leading, spacing: 8) {
    HStack {
     ProgressView()
     Text(statusText).foregroundStyle(.secondary)
     Spacer()
     Text(request.createdAt, style: .timer).monospacedDigit().foregroundStyle(.secondary)
    }
    if request.isCancellable {
     Button("Cancel Send", systemImage: "xmark.circle", role: .destructive) {
      Task { await store.cancel(request) }
     }
     .buttonStyle(.bordered)
    }
   }
  } else if request.isRetryable, isLatest {
   HStack {
    Label(statusText, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
    Spacer()
    Button("Ask again", systemImage: "arrow.clockwise") {
     Task { await store.retryAnswer(request) }
    }
    .buttonStyle(.bordered)
   }
  }
 }

 private var statusText: String {
  switch request.state {
  case .waitingForAttachments(let uploaded, let total): "Waiting for photos \(uploaded)/\(total)…"
  case .blocked: "A photo failed. Retry it, or cancel and remove it."
  case .queued, .processing: "Processing… you can put the iPhone away."
  case .completed: "Answer ready"
  case .failed(let reason): "No answer: \(reason)"
  case .cancelled: "Cancelled"
  }
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

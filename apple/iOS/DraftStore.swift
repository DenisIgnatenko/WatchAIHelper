import CopilotCore
import CoreGraphics
import Foundation
import Observation

/// State and actions of the iPhone draft screen (spec 23): photos, upload progress, optional text, Send.
///
/// Two kinds of state, kept apart on purpose (spec 53):
/// - **server state** (`draft`, `request`, `lastAnswer`): the backend is the source of truth;
/// - **local UI state** (`local`): thumbnails and upload progress that only this device knows.
/// The screen shows the server list of images, decorated with local thumbnails/progress where available.
@MainActor
@Observable
final class DraftStore {

 /// Local knowledge about one image of the draft.
 struct LocalImage {
  var thumbnail: CGImage?
  var phase: Phase

  enum Phase: Equatable {
   /// Resizing / hashing on the device.
   case preparing
   /// Declared to the backend, bytes on their way (fraction 0...1).
   case uploading(Double)
   case uploaded
   case failed(String)
  }
 }

 /// One tile of the draft screen.
 struct Tile: Identifiable {
  let id: UUID
  let position: Int
  let thumbnail: CGImage?
  let phase: LocalImage.Phase
 }

 private(set) var conversation: Conversation?
 /// All conversations for the picker (most recently updated first).
 private(set) var conversations: [Conversation] = []
 private(set) var draft: DraftDetail?
 private(set) var request: AIRequest?
 private(set) var lastAnswer: Message?
 private(set) var errorText: String?
 /// Images captured on this device, keyed by attachment id.
 private(set) var local: [UUID: LocalImage] = [:]
 /// Images captured but not yet registered on the backend (shown first, keep capture order).
 private(set) var unregistered: [UUID] = []
 /// Optional question typed on the iPhone.
 var text = ""

 private let service: any CopilotService & DraftEditingService
 private let observer: LongPollRequestObserver
 private var uploads: UploadManager!
 private var observation: Task<Void, Never>?
 /// Registrations run one after another: the backend numbers images in registration order,
 /// so this keeps the page order exactly as captured / selected (spec 27).
 private var registrationChain: Task<Void, Never>?

 init(service: any CopilotService & DraftEditingService, makeUploads: (@escaping @Sendable (UploadManager.Event) -> Void) -> UploadManager) {
  self.service = service
  self.observer = LongPollRequestObserver(service: service)
  // Upload events arrive on a background queue; hop to the main actor before touching state.
  self.uploads = makeUploads { [weak self] event in
   Task { @MainActor in self?.handle(event) }
  }
 }

 var uploadManager: UploadManager { uploads }

 // MARK: - Derived UI state

 /// Tiles in message order: server-known images first (by position), then images still being prepared.
 var tiles: [Tile] {
  let server = (draft?.attachments ?? []).map { attachment in
   let localImage = local[attachment.id]
   let phase: LocalImage.Phase = switch attachment.state {
   case .uploaded: .uploaded
   case .failed: .failed("Upload failed")
   // Pending on the server: show local progress if this device is uploading it.
   case .pending: localImage?.phase ?? .uploading(0)
   }
   return Tile(id: attachment.id, position: attachment.position, thumbnail: localImage?.thumbnail, phase: phase)
  }
  let preparing = unregistered.map { id in
   Tile(id: id, position: Int.max, thumbnail: local[id]?.thumbnail, phase: local[id]?.phase ?? .preparing)
  }
  return server + preparing
 }

 var canSend: Bool {
  let hasContent = !tiles.isEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  let hasFailure = tiles.contains { if case .failed = $0.phase { true } else { false } }
  let busy = request.map { !$0.state.isTerminal } ?? false
  return hasContent && !hasFailure && !busy && unregistered.isEmpty
 }

 // MARK: - Loading

 func refresh() async {
  do {
   let home = try await service.home()
   conversation = home.activeConversation
   lastAnswer = home.lastAnswer
   draft = try await service.currentDraft(conversationId: home.activeConversation.id)
   errorText = nil
  } catch {
   errorText = Self.describe(error)
  }
 }

 // MARK: - Choosing the conversation (the one that receives photos, questions and answers)

 /// The active conversation is stored on the backend, so the Watch switches too (spec 6).
 func loadConversations() async {
  conversations = (try? await service.conversations()) ?? conversations
 }

 func select(_ conversation: Conversation) async {
  do {
   try await service.setActiveConversation(id: conversation.id)
   await resetForConversationChange()
  } catch {
   errorText = Self.describe(error)
  }
 }

 func newConversation(mode: ConversationMode) async {
  do {
   _ = try await service.createConversation(mode: mode)
   await resetForConversationChange()
  } catch {
   errorText = Self.describe(error)
  }
 }

 private func resetForConversationChange() async {
  observation?.cancel()
  request = nil
  // Photos of the previous conversation's draft stay there; only local decorations are dropped.
  local = [:]
  unregistered = []
  await refresh()
  await loadConversations()
 }

 // MARK: - Adding images (never starts AI inference - Invariant 2)

 /// Called when the user confirms a photo ("Use") or picks one from the library.
 /// Prepares (in parallel), registers (strictly in call order) and starts the background upload.
 func addPhoto(_ data: Data, source: AttachmentInfo.Source) {
  let id = UUID()
  local[id] = LocalImage(thumbnail: nil, phase: .preparing)
  unregistered.append(id)
  // Heavy work (decode 24 MP, resize, encode, hash) starts at once, off the main thread.
  let preparation = Task.detached(priority: .userInitiated) {
   try ImageNormalizer.prepare(data, id: id)
  }
  let previous = registrationChain
  registrationChain = Task {
   await previous?.value
   await registerAndUpload(id: id, preparation: preparation, source: source)
  }
 }

 private func registerAndUpload(id: UUID, preparation: Task<PreparedImage, Error>, source: AttachmentInfo.Source) async {
  do {
   let prepared = try await preparation.value
   local[id]?.thumbnail = ImageNormalizer.thumbnail(of: prepared.fileURL)
   if draft == nil { await refresh() }
   guard let draftId = draft?.id else { throw CopilotServiceError.unavailable }
   _ = try await service.registerAttachment(draftId: draftId, registration: AttachmentRegistration(
    id: id, source: source, byteSize: prepared.byteSize, sha256: prepared.sha256,
    width: prepared.width, height: prepared.height
   ))
   local[id]?.phase = .uploading(0)
   unregistered.removeAll { $0 == id }
   uploads.upload(attachmentId: id, fileURL: prepared.fileURL)
   await refreshDraft()
  } catch {
   local[id]?.phase = .failed(Self.describe(error))
   errorText = Self.describe(error)
  }
 }

 /// Retry = upload the same file again (same id, so the backend cannot get a duplicate - spec 44).
 func retry(_ id: UUID) {
  let file = ImageNormalizer.fileURL(for: id)
  guard FileManager.default.fileExists(atPath: file.path) else {
   errorText = "The photo is no longer on this iPhone. Remove it and take it again."
   return
  }
  local[id, default: LocalImage(thumbnail: ImageNormalizer.thumbnail(of: file), phase: .uploading(0))].phase = .uploading(0)
  uploads.upload(attachmentId: id, fileURL: file)
 }

 func remove(_ id: UUID) async {
  guard let draftId = draft?.id else { return }
  do {
   try await service.removeAttachment(draftId: draftId, attachmentId: id)
   local[id] = nil
   try? FileManager.default.removeItem(at: ImageNormalizer.fileURL(for: id))
   await refreshDraft()
  } catch {
   errorText = Self.describe(error)
  }
 }

 // MARK: - Send (the only action that starts AI inference - Invariant 5)

 func send() async {
  guard let draftId = draft?.id else { return }
  let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
  do {
   let submitted = try await service.submit(draftId: draftId, text: question.isEmpty ? nil : question, idempotencyKey: UUID())
   text = ""
   observe(submitted)
   await refresh()
  } catch {
   // The typed text stays in the field (spec 43: never discard user input).
   errorText = Self.describe(error)
   await refresh()
  }
 }

 private func observe(_ submitted: AIRequest) {
  observation?.cancel()
  request = submitted
  observation = Task { [observer] in
   do {
    for try await update in observer.updates(of: submitted) {
     request = update
     if update.state.isTerminal { await refresh() }
    }
   } catch {
    errorText = "Connection lost. The answer will appear on the Watch."
   }
  }
 }

 // MARK: - Upload events

 private func handle(_ event: UploadManager.Event) {
  switch event {
  case .progress(let id, let fraction):
   local[id, default: LocalImage(thumbnail: nil, phase: .uploading(0))].phase = .uploading(fraction)
  case .finished(let id):
   local[id]?.phase = .uploaded
   Task { await refreshDraft() }
  case .failed(let id, let reason):
   local[id, default: LocalImage(thumbnail: nil, phase: .failed(reason))].phase = .failed(reason)
  }
 }

 private func refreshDraft() async {
  guard let conversationId = conversation?.id else { return }
  if let fresh = try? await service.currentDraft(conversationId: conversationId) {
   draft = fresh
  }
 }

 private static func describe(_ error: Error) -> String {
  switch error as? CopilotServiceError {
  case .draftAlreadySubmitted: "Already sent from another device."
  case .draftNotEditable: "This draft was already sent."
  case .emptyDraft: "Add a photo or a question."
  case .notFound: "Not found."
  case .unauthorized: "Device not authorized."
  case .unavailable: "Server unavailable."
  case nil: error.localizedDescription
  }
 }
}

import CopilotCore
import CoreGraphics
import Foundation
import Observation

/// Everything the iPhone app needs from the backend (the Watch uses only `CopilotService`).
typealias IPhoneService = CopilotService & DraftEditingService & UsageReportingService

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
  /// Set once the photo is resized and hashed. Kept so that a failed registration can be retried
  /// without the original photo (only the prepared file stays on the device).
  var prepared: PreparedImage?
  let source: AttachmentInfo.Source

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
 /// The latest request of the active conversation (to offer Retry after a failure, also after relaunch).
 private(set) var latestRequest: AIRequest?
 private(set) var errorText: String?
 /// Images captured on this device, keyed by attachment id.
 private(set) var local: [UUID: LocalImage] = [:]
 /// Images captured but not yet registered on the backend (shown first, keep capture order).
 private(set) var unregistered: [UUID] = []
 /// Optional question typed on the iPhone.
 var text = ""

 let service: any IPhoneService
 private let observer: LongPollRequestObserver
 private var uploads: UploadManager!
 private var observation: Task<Void, Never>?
 /// Registrations run one after another: the backend numbers images in registration order,
 /// so this keeps the page order exactly as captured / selected (spec 27).
 private var registrationChain: Task<Void, Never>?

 init(service: any IPhoneService, makeUploads: (@escaping @Sendable (UploadManager.Event) -> Void) -> UploadManager) {
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

 /// The request whose state is shown: the one being followed, otherwise the latest of the conversation.
 var visibleRequest: AIRequest? {
  request ?? latestRequest
 }

 // MARK: - Loading

 func refresh() async {
  do {
   let home = try await service.home()
   conversation = home.activeConversation
   lastAnswer = home.lastAnswer
   latestRequest = home.latestRequest
   // A Send from the Watch (or a previous session) is still running: follow it.
   if let latest = home.latestRequest, !latest.state.isTerminal, request?.id != latest.id {
    observe(latest)
   }
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

 /// A user-given title is final: the AI never replaces it.
 func rename(_ conversation: Conversation, to title: String) async {
  do {
   let renamed = try await service.renameConversation(id: conversation.id, title: title)
   if self.conversation?.id == renamed.id { self.conversation = renamed }
   await loadConversations()
  } catch {
   errorText = Self.describe(error)
  }
 }

 /// Deletes messages and photos on the server (spec 47). The view confirms first: it cannot be undone.
 func delete(_ conversation: Conversation) async {
  do {
   try await service.deleteConversation(id: conversation.id)
   if self.conversation?.id == conversation.id {
    // The backend switched the active conversation; the draft screen follows it.
    await resetForConversationChange()
   } else {
    await loadConversations()
   }
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
  local[id] = LocalImage(thumbnail: nil, phase: .preparing, source: source)
  unregistered.append(id)
  // Heavy work (decode 24 MP, resize, encode, hash) starts at once, off the main thread.
  let preparation = Task.detached(priority: .userInitiated) {
   try ImageNormalizer.prepare(data, id: id)
  }
  let previous = registrationChain
  registrationChain = Task {
   await previous?.value
   await registerAndUpload(id: id, preparation: preparation)
  }
 }

 private func registerAndUpload(id: UUID, preparation: Task<PreparedImage, Error>) async {
  do {
   let prepared = try await preparation.value
   local[id]?.prepared = prepared
   local[id]?.thumbnail = ImageNormalizer.thumbnail(of: prepared.fileURL)
   try await register(id: id, prepared: prepared)
   local[id]?.phase = .uploading(0)
   unregistered.removeAll { $0 == id }
   uploads.upload(attachmentId: id, fileURL: prepared.fileURL)
   await refreshDraft()
  } catch {
   local[id]?.phase = .failed(Self.describe(error))
   errorText = Self.describe(error)
  }
 }

 /// Step 1 of 2 (metadata). If the draft we know is gone or already sent (the Watch pressed Send, a cancelled
 /// Send merged drafts), the photo goes to the current draft instead: refresh once and register again.
 private func register(id: UUID, prepared: PreparedImage) async throws {
  let registration = AttachmentRegistration(
   id: id, source: local[id]?.source ?? .camera, byteSize: prepared.byteSize, sha256: prepared.sha256,
   width: prepared.width, height: prepared.height
  )
  if draft == nil { await refresh() }
  guard let draftId = draft?.id else { throw CopilotServiceError.unavailable }
  do {
   _ = try await service.registerAttachment(draftId: draftId, registration: registration)
  } catch CopilotServiceError.notFound, CopilotServiceError.draftNotEditable {
   await refresh()
   guard let currentId = draft?.id, currentId != draftId else { throw CopilotServiceError.draftNotEditable }
   _ = try await service.registerAttachment(draftId: currentId, registration: registration)
  }
 }

 /// Retry of a failed photo. Two different failures, two different fixes:
 /// - never registered on the backend (e.g. no network when "Use" was tapped): register first, then upload;
 /// - registered, but the bytes did not arrive: upload the same file again.
 /// The same id is used in both cases, so the backend cannot get a duplicate (spec 44).
 func retry(_ id: UUID) {
  let file = ImageNormalizer.fileURL(for: id)
  guard FileManager.default.fileExists(atPath: file.path) else {
   errorText = "The photo is no longer on this iPhone. Remove it and take it again."
   return
  }
  errorText = nil
  if unregistered.contains(id) {
   guard let prepared = local[id]?.prepared else {
    errorText = "The photo could not be prepared. Remove it and take it again."
    return
   }
   local[id]?.phase = .preparing
   let previous = registrationChain
   registrationChain = Task {
    await previous?.value
    await registerAndUpload(id: id, preparation: Task { () throws -> PreparedImage in prepared })
   }
   return
  }
  local[id, default: LocalImage(thumbnail: ImageNormalizer.thumbnail(of: file), phase: .uploading(0), source: .camera)]
   .phase = .uploading(0)
  uploads.upload(attachmentId: id, fileURL: file)
 }

 func remove(_ id: UUID) async {
  // Never reached the backend: only this iPhone knows about it.
  if unregistered.contains(id) {
   unregistered.removeAll { $0 == id }
   local[id] = nil
   try? FileManager.default.removeItem(at: ImageNormalizer.fileURL(for: id))
   return
  }
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

 /// Cancel Send while it waits for photos (spec 26): the photos and the text return to the draft.
 func cancel(_ submitted: AIRequest) async {
  do {
   let cancelled = try await service.cancelRequest(id: submitted.id)
   observation?.cancel()
   request = cancelled
   if text.isEmpty, let kept = try? await service.currentDraft(conversationId: submitted.conversationId).text {
    // The backend kept the question with the photos; show it in the field again.
    text = kept
   }
   await refresh()
  } catch {
   errorText = Self.describe(error)
   await refresh()
  }
 }

 /// Ask again after a failed answer: the same question, no duplicate message.
 func retryAnswer(_ failed: AIRequest) async {
  do {
   observe(try await service.retryRequest(id: failed.id))
   errorText = nil
  } catch {
   errorText = Self.describe(error)
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
   local[id, default: LocalImage(thumbnail: nil, phase: .uploading(0), source: .camera)].phase = .uploading(fraction)
  case .finished(let id):
   local[id]?.phase = .uploaded
   Task { await refreshDraft() }
  case .failed(let id, let reason):
   local[id, default: LocalImage(thumbnail: nil, phase: .failed(reason), source: .camera)].phase = .failed(reason)
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
  case .requestNotCancellable: "Too late to cancel: the question is already with the AI."
  case .requestNotRetryable: "Newer messages exist. Ask the question again."
  case .invalidTitle: "The title must have 1 to 80 characters."
  case nil: error.localizedDescription
  }
 }
}

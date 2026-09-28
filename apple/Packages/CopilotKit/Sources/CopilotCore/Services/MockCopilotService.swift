import Foundation

/// In-memory stand-in for the backend (Phase 1: "Watch -> mock backend -> response").
///
/// It imitates the backend *semantics* that matter to the UI:
/// - one current draft per conversation;
/// - Send is idempotent by `idempotencyKey`; a second Send of the same draft is rejected (spec 37);
/// - a draft with uploading images waits (architecture option B), then processes, then completes;
/// - the user message appears only once all images are uploaded (Invariant 6).
///
/// Swift notes:
/// - `actor` is a class whose state is protected by the compiler: only one caller runs inside it
///  at a time (like every method being `synchronized`, but without blocking threads - callers `await`).
///  Mutable in-memory state + concurrent callers is exactly what actors are for.
/// - State is advanced lazily from timestamps (`advance()`) instead of background timers:
///  no hidden tasks, deterministic tests (KISS).
public actor MockCopilotService: CopilotService {

 /// Initial state of the active conversation's draft, to exercise the Watch draft card.
 public enum DraftScenario: Sendable {
  /// No attachments: Watch questions are text-only.
  case empty
  /// N photos already uploaded from the "iPhone".
  case photosReady(Int)
  /// N photos that finish uploading one by one, every `uploadInterval`.
  case photosUploading(Int)
 }

 /// Timing knobs. Tests set them to zero; the demo uses realistic values.
 public struct Timing: Sendable {
  public var processing: Duration
  public var uploadInterval: Duration
  /// Granularity of the long-poll loop.
  public var pollStep: Duration

  public init(processing: Duration, uploadInterval: Duration, pollStep: Duration) {
   self.processing = processing
   self.uploadInterval = uploadInterval
   self.pollStep = pollStep
  }

  public static let demo = Timing(processing: .seconds(2), uploadInterval: .seconds(3), pollStep: .milliseconds(200))
  public static let instant = Timing(processing: .zero, uploadInterval: .zero, pollStep: .milliseconds(1))
 }

 // MARK: - Internal records (mutable, private to the actor)

 private struct DraftRecord {
  let id: UUID
  let conversationId: UUID
  let totalAttachments: Int
  /// Images already uploaded at creation time.
  let initiallyUploaded: Int
  /// Reference point for simulated uploads of the remaining images.
  let createdAt: ContinuousClock.Instant
  var submittedRequestId: UUID?
 }

 private struct RequestRecord {
  let id: UUID
  let conversationId: UUID
  let draftId: UUID
  let text: String?
  /// Moment when all attachments became available (processing starts from here).
  var queuedAt: ContinuousClock.Instant?
  var userMessageId: UUID?
  var assistantMessageId: UUID?
 }

 // MARK: - State

 private let timing: Timing
 private let clock = ContinuousClock()
 private var conversationsById: [UUID: Conversation] = [:]
 private var messagesByConversation: [UUID: [Message]] = [:]
 private var activeConversationId: UUID
 /// Current (not yet submitted) draft id per conversation.
 private var currentDraftByConversation: [UUID: UUID] = [:]
 private var drafts: [UUID: DraftRecord] = [:]
 private var requests: [UUID: RequestRecord] = [:]
 private var requestByIdempotencyKey: [UUID: UUID] = [:]

 // MARK: - Init

 /// - Parameter seedDemoConversation: pre-fill the conversation with an exam example
 ///  (used to review the conversation screen layout in the simulator).
 public init(scenario: DraftScenario = .empty, timing: Timing = .demo, seedDemoConversation: Bool = false) {
  self.timing = timing
  let conversation = Conversation(id: UUID(), title: "Danish exam", updatedAt: Date())
  self.activeConversationId = conversation.id
  self.conversationsById[conversation.id] = conversation
  self.messagesByConversation[conversation.id] = seedDemoConversation ? Self.demoMessages(conversationId: conversation.id) : []

  let (total, uploaded): (Int, Int) = switch scenario {
  case .empty: (0, 0)
  case .photosReady(let count): (count, count)
  case .photosUploading(let count): (count, 0)
  }
  // Actor initializers may touch stored properties directly; helper methods cannot be called yet,
  // so the first draft is created inline.
  let draft = DraftRecord(
   id: UUID(), conversationId: conversation.id,
   totalAttachments: total, initiallyUploaded: uploaded,
   createdAt: clock.now, submittedRequestId: nil
  )
  self.drafts[draft.id] = draft
  self.currentDraftByConversation[conversation.id] = draft.id
 }

 // MARK: - CopilotService

 public func home() async throws -> HomeSnapshot {
  advance()
  guard let conversation = conversationsById[activeConversationId] else { throw CopilotServiceError.notFound }
  let draftId = currentDraftId(for: conversation.id)
  let latest = requests.values
   .filter { $0.conversationId == conversation.id }
   // Most recent request = the one with the latest draft creation time.
   .max { (drafts[$0.draftId]?.createdAt ?? clock.now) < (drafts[$1.draftId]?.createdAt ?? clock.now) }
  return HomeSnapshot(
   activeConversation: conversation,
   draft: summary(of: draftId),
   latestRequest: latest.map(snapshot(of:)),
   lastAnswer: messagesByConversation[conversation.id]?.last { $0.role == .assistant }
  )
 }

 public func conversations() async throws -> [Conversation] {
  conversationsById.values.sorted { $0.updatedAt > $1.updatedAt }
 }

 public func createConversation() async throws -> Conversation {
  let conversation = Conversation(id: UUID(), title: "New conversation", updatedAt: Date())
  conversationsById[conversation.id] = conversation
  messagesByConversation[conversation.id] = []
  activeConversationId = conversation.id
  return conversation
 }

 public func setActiveConversation(id: UUID) async throws {
  guard conversationsById[id] != nil else { throw CopilotServiceError.notFound }
  activeConversationId = id
 }

 public func messages(conversationId: UUID) async throws -> [Message] {
  advance()
  guard let messages = messagesByConversation[conversationId] else { throw CopilotServiceError.notFound }
  return messages
 }

 public func submit(draftId: UUID, text: String?, idempotencyKey: UUID) async throws -> AIRequest {
  // 1. Same key again (network retry) -> the same request, nothing new is created.
  if let existingId = requestByIdempotencyKey[idempotencyKey], let existing = requests[existingId] {
   return snapshot(of: existing)
  }
  guard let draft = drafts[draftId] else { throw CopilotServiceError.notFound }
  // 2. Draft already sent (e.g. from the iPhone with another key) -> conflict, caller keeps its text.
  if draft.submittedRequestId != nil { throw CopilotServiceError.draftAlreadySubmitted }
  // 3. Nothing to send.
  let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
  let normalizedText = (trimmed?.isEmpty ?? true) ? nil : trimmed
  if normalizedText == nil && draft.totalAttachments == 0 { throw CopilotServiceError.emptyDraft }

  // Freeze the draft and start a fresh one for the next question.
  let request = RequestRecord(id: UUID(), conversationId: draft.conversationId, draftId: draft.id, text: normalizedText)
  requests[request.id] = request
  requestByIdempotencyKey[idempotencyKey] = request.id
  drafts[draft.id]?.submittedRequestId = request.id
  currentDraftByConversation[draft.conversationId] = nil

  advance()
  return snapshot(of: requests[request.id]!)
 }

 public func request(id: UUID, waitSeconds: Int) async throws -> AIRequest {
  guard requests[id] != nil else { throw CopilotServiceError.notFound }
  advance()
  let initial = snapshot(of: requests[id]!)
  let deadline = clock.now.advanced(by: .seconds(waitSeconds))
  // Long-poll: return on change, on terminal state or at the deadline.
  // `Task.sleep` suspends only this call; while it sleeps, other callers may enter the actor.
  while clock.now < deadline && !initial.state.isTerminal {
   try await Task.sleep(for: timing.pollStep)
   advance()
   let current = snapshot(of: requests[id]!)
   if current != initial { return current }
  }
  return snapshot(of: requests[id]!)
 }

 // MARK: - Simulation

 /// Moves every request forward according to elapsed time.
 private func advance() {
  let now = clock.now
  for id in requests.keys {
   guard var request = requests[id], request.assistantMessageId == nil else { continue }
   // Waiting -> queued once all attachments are "uploaded". Only now the user message is created.
   if request.queuedAt == nil, uploadedCount(of: request.draftId, at: now) == drafts[request.draftId]!.totalAttachments {
    request.queuedAt = now
    request.userMessageId = append(Message(
     id: UUID(), conversationId: request.conversationId, role: .user,
     text: request.text, attachmentCount: drafts[request.draftId]!.totalAttachments, createdAt: Date()
    ))
   }
   // Processing -> completed after the simulated inference time.
   if let queuedAt = request.queuedAt, now >= queuedAt.advanced(by: timing.processing) {
    request.assistantMessageId = append(answer(for: request))
   }
   requests[id] = request
  }
 }

 private func uploadedCount(of draftId: UUID, at now: ContinuousClock.Instant) -> Int {
  guard let draft = drafts[draftId] else { return 0 }
  let remaining = draft.totalAttachments - draft.initiallyUploaded
  guard remaining > 0 else { return draft.totalAttachments }
  guard timing.uploadInterval > .zero else { return draft.totalAttachments }
  let elapsed = draft.createdAt.duration(to: now)
  let finished = Int(elapsed / timing.uploadInterval)
  return draft.initiallyUploaded + min(remaining, finished)
 }

 private func append(_ message: Message) -> UUID {
  messagesByConversation[message.conversationId, default: []].append(message)
  conversationsById[message.conversationId]?.updatedAt = message.createdAt
  return message.id
 }

 /// Canned answers. For text questions the answer echoes the input with its Unicode scalars,
 /// which is exactly what device check V1-V3 (Russian / Danish / English input) needs to see.
 private func answer(for request: RequestRecord) -> Message {
  let attachments = drafts[request.draftId]?.totalAttachments ?? 0
  let text: String
  if attachments > 0 {
   text = "1 — B\n2 — C\n3 — A\n4 — B\n5 — D\n\n(mock: \(attachments) photos"
    + (request.text.map { ", prompt: «\($0)»" } ?? "") + ")"
  } else {
   let input = request.text ?? ""
   text = "Mock answer.\n\n«\(input)»\n\nCharacters: \(input.count)\nScalars: \(input.unicodeScalars.count)"
  }
  return Message(
   id: UUID(), conversationId: request.conversationId, role: .assistant, text: text,
   suggestedActions: [
    SuggestedAction(title: "Подробнее", prompt: "Объясни подробнее."),
    SuggestedAction(title: "Пример", prompt: "Приведи пример."),
   ],
   createdAt: Date()
  )
 }

 /// The spec 67 scenario: three photographed pages, answers, a follow-up about question 4.
 private static func demoMessages(conversationId: UUID) -> [Message] {
  let actions = [
   SuggestedAction(title: "Подробнее", prompt: "Объясни подробнее."),
   SuggestedAction(title: "Пример", prompt: "Приведи пример."),
  ]
  return [
   Message(id: UUID(), conversationId: conversationId, role: .user, text: "Ответь на вопросы.", attachmentCount: 3, createdAt: Date()),
   Message(id: UUID(), conversationId: conversationId, role: .assistant, text: "1 — B\n2 — C\n3 — A\n4 — B\n5 — D", createdAt: Date()),
   Message(id: UUID(), conversationId: conversationId, role: .user, text: "Почему 4 B?", createdAt: Date()),
   Message(
    id: UUID(), conversationId: conversationId, role: .assistant,
    text: "4 — B\n\n«Mens» означает одновременные действия. Здесь второе действие происходит после первого, поэтому подходит «efter at» (B).",
    suggestedActions: actions, createdAt: Date()
   ),
  ]
 }

 // MARK: - Mapping records -> domain values

 /// Returns the current draft id, creating an empty draft lazily (like the backend's get-or-create).
 private func currentDraftId(for conversationId: UUID) -> UUID {
  if let id = currentDraftByConversation[conversationId] { return id }
  let draft = DraftRecord(
   id: UUID(), conversationId: conversationId, totalAttachments: 0, initiallyUploaded: 0,
   createdAt: clock.now, submittedRequestId: nil
  )
  drafts[draft.id] = draft
  currentDraftByConversation[conversationId] = draft.id
  return draft.id
 }

 private func summary(of draftId: UUID) -> DraftSummary {
  let draft = drafts[draftId]!
  return DraftSummary(
   id: draft.id,
   totalAttachments: draft.totalAttachments,
   uploadedAttachments: uploadedCount(of: draftId, at: clock.now)
  )
 }

 private func snapshot(of request: RequestRecord) -> AIRequest {
  let state: AIRequest.State
  if let answerId = request.assistantMessageId {
   state = .completed(assistantMessageId: answerId)
  } else if request.queuedAt != nil {
   state = .processing
  } else {
   let total = drafts[request.draftId]?.totalAttachments ?? 0
   state = .waitingForAttachments(uploaded: uploadedCount(of: request.draftId, at: clock.now), total: total)
  }
  return AIRequest(id: request.id, conversationId: request.conversationId, state: state)
 }
}

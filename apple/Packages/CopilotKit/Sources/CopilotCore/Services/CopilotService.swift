import Foundation

/// The client-side contract with the backend (architecture section 3).
///
/// Dependency Inversion: views and models depend on this protocol, not on a concrete network client.
/// This pays off immediately, not speculatively:
/// - Phase 1: the Watch app runs against `MockCopilotService` (no backend exists yet);
/// - tests use the mock;
/// - Phase 2: `LiveCopilotService` (HTTP) replaces it in one line of the composition root.
///
/// Swift notes:
/// - `protocol` is Swift's interface.
/// - `async throws` = the call suspends without blocking a thread and may fail
///  (roughly `CompletableFuture<T>` + checked exception, but written as straight-line code with `try await`).
/// - `Sendable` on the protocol lets one service instance be used from any concurrent task.
public protocol CopilotService: Sendable {
 /// One-call snapshot for the Watch main screen.
 func home() async throws -> HomeSnapshot

 /// All conversations, most recently updated first.
 func conversations() async throws -> [Conversation]

 /// Creates an empty conversation and makes it active on all devices.
 func createConversation() async throws -> Conversation

 /// Makes a conversation active on all devices (spec 6).
 func setActiveConversation(id: UUID) async throws

 /// Messages of a conversation in their stable order.
 func messages(conversationId: UUID) async throws -> [Message]

 /// Explicit Send (spec 25). The only operation that starts AI inference (Invariant 5).
 ///
 /// - Parameters:
 ///  - draftId: the draft to submit. Text-only questions use the current (empty) draft,
 ///   so there is exactly one submission path for every message type (DRY).
 ///  - text: optional text; for a draft with images it becomes the text of that message (decision Q1).
 ///  - idempotencyKey: generated once per user tap. Retrying with the same key never creates a second request (spec 37).
 func submit(draftId: UUID, text: String?, idempotencyKey: UUID) async throws -> AIRequest

 /// Current state of a request. With `waitSeconds > 0` the call returns as soon as the state changes
 /// or when the time runs out (long-poll), whichever comes first.
 func request(id: UUID, waitSeconds: Int) async throws -> AIRequest
}

/// Errors every `CopilotService` implementation maps its failures to, so the UI handles one error type.
public enum CopilotServiceError: Error, Equatable, Sendable {
 /// The draft was already sent from another device (backend `409`). The user's typed text must be kept.
 case draftAlreadySubmitted
 /// The draft was already sent; new images belong to the next draft (backend `409`).
 case draftNotEditable
 /// The draft has neither text nor attachments.
 case emptyDraft
 case notFound
 /// Missing or invalid device token (backend `401`): the app is not configured correctly.
 case unauthorized
 /// Network or backend unavailable. Safe to retry with the same idempotency key.
 case unavailable
}

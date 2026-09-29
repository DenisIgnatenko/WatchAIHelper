import Foundation

/// One AI inference request created by an explicit Send (spec 36, architecture section 9).
public struct AIRequest: Identifiable, Hashable, Sendable {
 public let id: UUID
 public let conversationId: UUID
 public let state: State
 /// When Send was pressed. Screens and the complication show the elapsed time from here.
 public let createdAt: Date

 public init(id: UUID, conversationId: UUID, state: State, createdAt: Date) {
  self.id = id
  self.conversationId = conversationId
  self.state = state
  self.createdAt = createdAt
 }

 /// The user may still cancel: nothing was sent to the AI yet (spec 26).
 public var isCancellable: Bool {
  switch state {
  case .waitingForAttachments, .blocked: true
  default: false
  }
 }

 /// The AI failed after the backend's own retries; the user may ask again for the same question.
 public var isRetryable: Bool {
  if case .failed = state { return true }
  return false
 }

 /// Mirrors the backend state machine. The backend is the only place where transitions happen;
 /// the client only displays the state it receives.
 public enum State: Hashable, Sendable {
  /// Send accepted, some images are still uploading.
  case waitingForAttachments(uploaded: Int, total: Int)
  /// An image failed; the user must retry, remove it or cancel.
  case blocked(failedAttachments: Int)
  /// Complete message created, waiting for a worker.
  case queued
  /// The backend is talking to OpenAI.
  case processing
  /// The answer is stored as an assistant message.
  case completed(assistantMessageId: UUID)
  /// Inference failed after backend retries. `reason` is safe to show to the user.
  case failed(reason: String)
  /// The user cancelled the Send; the draft is editable again.
  case cancelled

  /// Terminal states never change again, so observation can stop.
  public var isTerminal: Bool {
   switch self {
   case .completed, .failed, .cancelled: true
   case .waitingForAttachments, .blocked, .queued, .processing: false
   }
  }
 }
}

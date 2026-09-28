import Foundation

/// Everything the Watch main screen needs, fetched in one call (`GET /v1/home`, architecture section 6).
///
/// One request instead of four keeps the Watch fast: every round trip goes Watch -> iPhone (Bluetooth)
/// -> internet, so the number of calls matters more than their size.
public struct HomeSnapshot: Hashable, Sendable {
 public let activeConversation: Conversation
 /// The current draft of the active conversation. The backend always provides one
 /// (created lazily), so a text question from the Watch always has a draft to submit.
 public let draft: DraftSummary
 /// The most recent request of the active conversation, if any.
 public let latestRequest: AIRequest?
 /// Preview of the latest assistant answer.
 public let lastAnswer: Message?

 public init(
  activeConversation: Conversation,
  draft: DraftSummary,
  latestRequest: AIRequest?,
  lastAnswer: Message?
 ) {
  self.activeConversation = activeConversation
  self.draft = draft
  self.latestRequest = latestRequest
  self.lastAnswer = lastAnswer
 }
}

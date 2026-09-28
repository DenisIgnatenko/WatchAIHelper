import Foundation

/// Who authored a message (spec 7).
public enum MessageRole: String, Hashable, Sendable {
 case user
 case assistant
}

/// A predefined follow-up offered under an assistant answer (spec 16).
/// Selecting it sends `prompt` to the same conversation.
public struct SuggestedAction: Hashable, Sendable {
 public let title: String
 public let prompt: String

 public init(title: String, prompt: String) {
  self.title = title
  self.prompt = prompt
 }
}

/// An immutable, already submitted message (spec 7, 8).
///
/// Clients never edit messages. That is why every property is `let`: the compiler
/// rejects any attempt to change a message after it has been created.
public struct Message: Identifiable, Hashable, Sendable {
 public let id: UUID
 public let conversationId: UUID
 public let role: MessageRole
 /// `nil` for image-only user messages (spec 28).
 public let text: String?
 /// The Watch shows only the number of images ("3 photos"), never the images themselves.
 public let attachmentCount: Int
 public let suggestedActions: [SuggestedAction]
 public let createdAt: Date

 public init(
  id: UUID,
  conversationId: UUID,
  role: MessageRole,
  text: String?,
  attachmentCount: Int = 0,
  suggestedActions: [SuggestedAction] = [],
  createdAt: Date
 ) {
  self.id = id
  self.conversationId = conversationId
  self.role = role
  self.text = text
  self.attachmentCount = attachmentCount
  self.suggestedActions = suggestedActions
  self.createdAt = createdAt
 }
}

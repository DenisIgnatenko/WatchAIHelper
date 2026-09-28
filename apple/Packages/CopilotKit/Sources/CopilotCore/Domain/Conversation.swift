import Foundation

// MARK: - Swift notes for readers coming from Java
//
// - `struct` is a value type: assigning or passing it copies it (like a Java record, but copyable
//  and optionally mutable). Domain models are structs so that no two screens can accidentally
//  share and mutate the same instance.
// - `Sendable` promises the compiler that the value is safe to pass between concurrent tasks.
//  Swift 6 checks this at compile time (similar in spirit to "effectively immutable" in Java).
// - `Hashable` / `Equatable` are synthesized automatically from the stored properties
//  (like a Java record's equals/hashCode).
// - `Identifiable` requires an `id` property; SwiftUI lists use it to track rows.

/// A conversation: an ordered sequence of messages shared by iPhone and Watch (spec 6).
public struct Conversation: Identifiable, Hashable, Sendable {
 public let id: UUID
 public var title: String
 /// Chosen at creation; decides the AI's instructions and study materials on the backend.
 public let mode: ConversationMode
 public var updatedAt: Date

 public init(id: UUID, title: String, mode: ConversationMode = .general, updatedAt: Date) {
  self.id = id
  self.title = title
  self.mode = mode
  self.updatedAt = updatedAt
 }
}

/// What a conversation is for.
public enum ConversationMode: Hashable, Sendable, CaseIterable {
 /// General assistant.
 case general
 /// Danish exam preparation (DU3): exam guide + official study materials are added on the backend.
 case danishExam

 public var displayName: String {
  switch self {
  case .general: "General"
  case .danishExam: "Danish exam"
  }
 }

 /// SF Symbol shown next to the conversation title.
 public var symbolName: String {
  switch self {
  case .general: "bubble.left.and.bubble.right"
  case .danishExam: "graduationcap"
  }
 }
}

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
 public var updatedAt: Date

 public init(id: UUID, title: String, updatedAt: Date) {
  self.id = id
  self.title = title
  self.updatedAt = updatedAt
 }
}

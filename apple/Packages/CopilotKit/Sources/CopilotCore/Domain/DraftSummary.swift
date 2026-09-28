import Foundation

/// What the Watch needs to know about the current draft of the active conversation (spec 30).
///
/// The Watch never manages attachments itself (that is the iPhone's job), so it receives
/// only counters, not the attachment list. Less data, simpler Watch code (KISS).
public struct DraftSummary: Hashable, Sendable {
 public let id: UUID
 public let text: String?
 public let totalAttachments: Int
 public let uploadedAttachments: Int
 public let failedAttachments: Int

 public init(
  id: UUID,
  text: String? = nil,
  totalAttachments: Int = 0,
  uploadedAttachments: Int = 0,
  failedAttachments: Int = 0
 ) {
  self.id = id
  self.text = text
  self.totalAttachments = totalAttachments
  self.uploadedAttachments = uploadedAttachments
  self.failedAttachments = failedAttachments
 }

 /// Attachments registered on the backend whose bytes have not arrived yet.
 public var pendingAttachments: Int {
  totalAttachments - uploadedAttachments - failedAttachments
 }

 /// A single value the UI can switch over, instead of re-deriving it from counters in every view (DRY).
 public var readiness: Readiness {
  if totalAttachments == 0 { return .noAttachments }
  if failedAttachments > 0 { return .hasFailures(failed: failedAttachments) }
  if pendingAttachments > 0 { return .uploading(uploaded: uploadedAttachments, total: totalAttachments) }
  return .ready(count: totalAttachments)
 }

 /// Swift enums can carry associated values per case (like a sealed interface with records in Java).
 public enum Readiness: Hashable, Sendable {
  /// Nothing attached: text sent from the Watch becomes a text-only message.
  case noAttachments
  /// Some images are still uploading from the iPhone. Send is allowed: the backend waits (architecture, option B).
  case uploading(uploaded: Int, total: Int)
  /// All images are on the backend.
  case ready(count: Int)
  /// At least one image failed. It must be fixed on the iPhone (Retry / Remove) - Invariant 6.
  case hasFailures(failed: Int)
 }
}

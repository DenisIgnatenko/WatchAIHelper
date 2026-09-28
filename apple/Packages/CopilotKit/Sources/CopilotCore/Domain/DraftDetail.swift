import Foundation

/// The editable draft with its images, as the iPhone draft screen needs it (spec 23).
/// The Watch uses the lighter `DraftSummary` instead.
public struct DraftDetail: Hashable, Sendable {
 public let id: UUID
 public let conversationId: UUID
 public let text: String?
 public let attachments: [AttachmentInfo]

 public init(id: UUID, conversationId: UUID, text: String?, attachments: [AttachmentInfo]) {
  self.id = id
  self.conversationId = conversationId
  self.text = text
  self.attachments = attachments
 }
}

/// Server-side state of one image of a draft.
public struct AttachmentInfo: Identifiable, Hashable, Sendable {
 public enum State: Hashable, Sendable { case pending, uploaded, failed }
 public enum Source: Hashable, Sendable { case camera, photoLibrary }

 public let id: UUID
 /// Order inside the message (1, 2, 3, ...), assigned by the backend.
 public let position: Int
 public let state: State
 public let source: Source
 public let byteSize: Int64

 public init(id: UUID, position: Int, state: State, source: Source, byteSize: Int64) {
  self.id = id
  self.position = position
  self.state = state
  self.source = source
  self.byteSize = byteSize
 }
}

/// What the iPhone declares before uploading an image (step 1 of 2).
public struct AttachmentRegistration: Sendable {
 public let id: UUID
 public let source: AttachmentInfo.Source
 public let byteSize: Int64
 /// Lower-case hex SHA-256 of the exact bytes that will be uploaded.
 public let sha256: String
 public let width: Int
 public let height: Int

 public init(id: UUID, source: AttachmentInfo.Source, byteSize: Int64, sha256: String, width: Int, height: Int) {
  self.id = id
  self.source = source
  self.byteSize = byteSize
  self.sha256 = sha256
  self.width = width
  self.height = height
 }
}

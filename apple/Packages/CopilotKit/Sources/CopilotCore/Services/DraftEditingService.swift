import Foundation

/// Draft and image operations used only by the iPhone app.
///
/// A separate protocol instead of more methods on `CopilotService` (Interface Segregation):
/// the Watch app and its mock never see or implement operations they do not use.
/// The upload of the bytes itself is not here: it runs in an iOS background URLSession (UploadManager).
public protocol DraftEditingService: Sendable {
 /// The editable draft of a conversation with its images (created lazily by the backend).
 func currentDraft(conversationId: UUID) async throws -> DraftDetail

 /// Step 1 of 2: declare an image. Idempotent by `registration.id`. Never starts AI inference.
 func registerAttachment(draftId: UUID, registration: AttachmentRegistration) async throws -> AttachmentInfo

 /// Removes an image from the editable draft. Idempotent.
 func removeAttachment(draftId: UUID, attachmentId: UUID) async throws
}

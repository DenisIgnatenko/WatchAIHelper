import CopilotAPI
import Foundation

/// Transport DTO -> domain model mapping (spec 52). The only place that knows the generated DTO shapes,
/// so a contract change touches this file and nothing in the UI.
enum DTOMapping {

 /// The contract promised a field value the client cannot interpret (e.g. an invalid UUID).
 struct InvalidPayload: Error {
  let field: String
 }

 static func home(_ dto: Components.Schemas.HomeSnapshot) throws -> HomeSnapshot {
  HomeSnapshot(
   activeConversation: try conversation(dto.activeConversation),
   draft: try draft(dto.draft),
   latestRequest: try dto.latestRequest.map(request),
   lastAnswer: try dto.lastAnswer.map(message)
  )
 }

 static func conversation(_ dto: Components.Schemas.Conversation) throws -> Conversation {
  Conversation(
   id: try uuid(dto.id, "conversation.id"),
   title: dto.title,
   mode: dto.mode == .danishExam ? .danishExam : .general,
   updatedAt: dto.updatedAt
  )
 }

 static func draft(_ dto: Components.Schemas.DraftSummary) throws -> DraftSummary {
  DraftSummary(
   id: try uuid(dto.id, "draft.id"),
   text: dto.text,
   totalAttachments: dto.totalAttachments,
   uploadedAttachments: dto.uploadedAttachments,
   failedAttachments: dto.failedAttachments
  )
 }

 static func message(_ dto: Components.Schemas.Message) throws -> Message {
  Message(
   id: try uuid(dto.id, "message.id"),
   conversationId: try uuid(dto.conversationId, "message.conversationId"),
   role: dto.role == .user ? .user : .assistant,
   text: dto.text,
   attachmentCount: dto.attachmentCount,
   suggestedActions: dto.suggestedActions.map { SuggestedAction(title: $0.title, prompt: $0.prompt) },
   createdAt: dto.createdAt
  )
 }

 /// The backend sends a flat object (state + optional details); the domain uses an enum with associated values.
 static func request(_ dto: Components.Schemas.AiRequest) throws -> AIRequest {
  let state: AIRequest.State = switch dto.state {
  case .waitingForAttachments:
   .waitingForAttachments(uploaded: dto.uploadedAttachments ?? 0, total: dto.totalAttachments ?? 0)
  case .blocked: .blocked(failedAttachments: dto.failedAttachments ?? 0)
  case .queued: .queued
  case .processing: .processing
  case .completed: .completed(assistantMessageId: try uuid(dto.assistantMessageId ?? "", "request.assistantMessageId"))
  case .failed: .failed(reason: dto.failureReason ?? "Could not get an answer")
  case .cancelled: .cancelled
  }
  return AIRequest(
   id: try uuid(dto.id, "request.id"),
   conversationId: try uuid(dto.conversationId, "request.conversationId"),
   state: state
  )
 }

 static func draftDetail(_ dto: Components.Schemas.DraftDetail) throws -> DraftDetail {
  DraftDetail(
   id: try uuid(dto.id, "draft.id"),
   conversationId: try uuid(dto.conversationId, "draft.conversationId"),
   text: dto.text,
   attachments: try dto.attachments.map(attachment)
  )
 }

 static func attachment(_ dto: Components.Schemas.Attachment) throws -> AttachmentInfo {
  let state: AttachmentInfo.State = switch dto.state {
  case .pending: .pending
  case .uploaded: .uploaded
  case .failed: .failed
  }
  return AttachmentInfo(
   id: try uuid(dto.id, "attachment.id"),
   position: dto.position,
   state: state,
   source: dto.source == .camera ? .camera : .photoLibrary,
   byteSize: dto.byteSize
  )
 }

 /// The OpenAPI generator represents `format: uuid` as `String`; parse it once, here.
 private static func uuid(_ value: String, _ field: String) throws -> UUID {
  guard let id = UUID(uuidString: value) else { throw InvalidPayload(field: field) }
  return id
 }
}

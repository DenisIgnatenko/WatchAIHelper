import CopilotAPI
import Foundation

/// iPhone-only draft operations over HTTPS (see `DraftEditingService`).
extension LiveCopilotService: DraftEditingService {

 public func currentDraft(conversationId: UUID) async throws -> DraftDetail {
  let output = try await call({
   try await client.getCurrentDraft(path: .init(conversationId: conversationId.uuidString))
  })
  switch output {
  case .ok(let ok): return try DTOMapping.draftDetail(ok.body.json)
  case .unauthorized: throw CopilotServiceError.unauthorized
  case .notFound: throw CopilotServiceError.notFound
  case .undocumented(let status, _): throw Self.error(forStatus: status)
  }
 }

 public func registerAttachment(draftId: UUID, registration: AttachmentRegistration) async throws -> AttachmentInfo {
  let body = Components.Schemas.RegisterAttachmentRequest(
   mimeType: .imageJpeg,
   byteSize: registration.byteSize,
   sha256: registration.sha256,
   source: registration.source == .camera ? .camera : .photoLibrary,
   width: registration.width,
   height: registration.height
  )
  let output = try await call({
   try await client.registerAttachment(
    path: .init(draftId: draftId.uuidString, attachmentId: registration.id.uuidString),
    body: .json(body)
   )
  })
  switch output {
  case .ok(let ok): return try DTOMapping.attachment(ok.body.json)
  case .conflict: throw CopilotServiceError.draftNotEditable
  case .unauthorized: throw CopilotServiceError.unauthorized
  case .notFound: throw CopilotServiceError.notFound
  case .undocumented(let status, _): throw Self.error(forStatus: status)
  }
 }

 public func removeAttachment(draftId: UUID, attachmentId: UUID) async throws {
  let output = try await call({
   try await client.removeAttachment(path: .init(draftId: draftId.uuidString, attachmentId: attachmentId.uuidString))
  })
  switch output {
  case .noContent: return
  case .conflict: throw CopilotServiceError.draftNotEditable
  case .unauthorized: throw CopilotServiceError.unauthorized
  case .notFound: throw CopilotServiceError.notFound
  case .undocumented(let status, _): throw Self.error(forStatus: status)
  }
 }
}

import Foundation
import Testing
@testable import CopilotCore

/// The mock is the Phase 1 "backend", so its semantics must match the real contract.
/// These tests also document that contract for the Phase 2 Java implementation.
struct MockCopilotServiceTests {

 @Test func textQuestionCompletesAndPreservesUnicode() async throws {
  let service = MockCopilotService(timing: .instant)
  let home = try await service.home()
  let question = "Hvad betyder selvom? Почему здесь Redis?"

  let request = try await service.submit(draftId: home.draft.id, text: question, idempotencyKey: UUID())
  let final = try await service.request(id: request.id, waitSeconds: 1)

  guard case .completed = final.state else {
   Issue.record("Expected completed, got \(final.state)")
   return
  }
  let messages = try await service.messages(conversationId: home.activeConversation.id)
  #expect(messages.map(\.role) == [.user, .assistant])
  #expect(messages.first?.text == question)
 }

 @Test func sameIdempotencyKeyReturnsSameRequest() async throws {
  let service = MockCopilotService(timing: .instant)
  let draftId = try await service.home().draft.id
  let key = UUID()

  let first = try await service.submit(draftId: draftId, text: "why kafka?", idempotencyKey: key)
  let retry = try await service.submit(draftId: draftId, text: "why kafka?", idempotencyKey: key)

  #expect(first.id == retry.id)
 }

 @Test func secondSendOfSameDraftIsRejected() async throws {
  // Watch and iPhone press Send on the same draft with different keys: exactly one wins.
  let service = MockCopilotService(scenario: .photosReady(3), timing: .instant)
  let draftId = try await service.home().draft.id

  _ = try await service.submit(draftId: draftId, text: nil, idempotencyKey: UUID())
  await #expect(throws: CopilotServiceError.draftAlreadySubmitted) {
   try await service.submit(draftId: draftId, text: "ответ 3?", idempotencyKey: UUID())
  }
 }

 @Test func emptyDraftCannotBeSent() async throws {
  let service = MockCopilotService(timing: .instant)
  let draftId = try await service.home().draft.id
  await #expect(throws: CopilotServiceError.emptyDraft) {
   try await service.submit(draftId: draftId, text: "   ", idempotencyKey: UUID())
  }
 }

 @Test func imageOnlyDraftIsValid() async throws {
  let service = MockCopilotService(scenario: .photosReady(3), timing: .instant)
  let home = try await service.home()
  #expect(home.draft.readiness == .ready(count: 3))

  let request = try await service.submit(draftId: home.draft.id, text: nil, idempotencyKey: UUID())
  _ = try await service.request(id: request.id, waitSeconds: 1)

  let userMessage = try await service.messages(conversationId: home.activeConversation.id).first
  #expect(userMessage?.text == nil)
  #expect(userMessage?.attachmentCount == 3)
 }

 @Test func uploadingDraftWaitsThenCompletes() async throws {
  let timing = MockCopilotService.Timing(processing: .zero, uploadInterval: .milliseconds(50), pollStep: .milliseconds(5))
  let service = MockCopilotService(scenario: .photosUploading(2), timing: timing)
  let home = try await service.home()

  let request = try await service.submit(draftId: home.draft.id, text: nil, idempotencyKey: UUID())
  #expect(request.state == .waitingForAttachments(uploaded: 0, total: 2))
  // No user message while images are missing (Invariant 6).
  #expect(try await service.messages(conversationId: home.activeConversation.id).isEmpty)

  let observer = LongPollRequestObserver(service: service, waitSeconds: 1)
  var last: AIRequest?
  for try await update in observer.updates(of: request) { last = update }

  guard case .completed = last?.state else {
   Issue.record("Expected completed, got \(String(describing: last?.state))")
   return
  }
 }

 @Test func sendingCreatesFreshDraft() async throws {
  let service = MockCopilotService(timing: .instant)
  let before = try await service.home().draft.id
  _ = try await service.submit(draftId: before, text: "ответ 3?", idempotencyKey: UUID())
  let after = try await service.home().draft.id
  #expect(before != after)
 }
}

import CopilotAPI
import Foundation
import Testing
@testable import CopilotCore

struct DateTranscoderTests {

 @Test func parsesTimestampsWithAndWithoutFraction() throws {
  let transcoder = FlexibleISO8601DateTranscoder()
  let precise = try transcoder.decode("2026-09-28T14:59:37.685246Z")
  let whole = try transcoder.decode("2026-09-28T14:59:37Z")
  #expect(precise.timeIntervalSince(whole) > 0.68)
  #expect(precise.timeIntervalSince(whole) < 0.69)
 }
}

struct DTOMappingTests {

 @Test func flatRequestBecomesDomainEnum() throws {
  let dto = Components.Schemas.AiRequest(
   id: UUID().uuidString, conversationId: UUID().uuidString, state: .waitingForAttachments,
   uploadedAttachments: 2, totalAttachments: 3
  )
  #expect(try DTOMapping.request(dto).state == .waitingForAttachments(uploaded: 2, total: 3))
 }

 @Test func invalidUUIDIsRejected() {
  let dto = Components.Schemas.AiRequest(id: "not-a-uuid", conversationId: UUID().uuidString, state: .queued)
  #expect(throws: DTOMapping.InvalidPayload.self) { try DTOMapping.request(dto) }
 }
}

/// End-to-end check of the generated client against a running backend.
/// Skipped unless both variables are set, e.g.:
///  COPILOT_E2E_URL=http://localhost:8080 COPILOT_E2E_TOKEN=... swift test --filter LiveServiceE2ETests
/// Costs one real OpenAI call.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["COPILOT_E2E_URL"] != nil))
struct LiveServiceE2ETests {

 @Test func askAndReceiveAnswer() async throws {
  let environment = ProcessInfo.processInfo.environment
  let service = LiveCopilotService(
   baseURL: try #require(URL(string: environment["COPILOT_E2E_URL"] ?? "")),
   deviceToken: environment["COPILOT_E2E_TOKEN"] ?? ""
  )
  let home = try await service.home()
  let request = try await service.submit(draftId: home.draft.id, text: "ответ 3?", idempotencyKey: UUID())

  var last = request
  for try await update in LongPollRequestObserver(service: service).updates(of: request) { last = update }

  guard case .completed(let answerId) = last.state else {
   Issue.record("Expected completed, got \(last.state)")
   return
  }
  let messages = try await service.messages(conversationId: home.activeConversation.id)
  #expect(messages.last?.id == answerId)
  #expect(messages.last?.text?.isEmpty == false)
 }
}

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
  let sentAt = Date(timeIntervalSince1970: 1_790_000_000)
  let dto = Components.Schemas.AiRequest(
   id: UUID().uuidString, conversationId: UUID().uuidString, createdAt: sentAt, state: .waitingForAttachments,
   uploadedAttachments: 2, totalAttachments: 3
  )
  let request = try DTOMapping.request(dto)
  #expect(request.state == .waitingForAttachments(uploaded: 2, total: 3))
  #expect(request.createdAt == sentAt)
  #expect(request.isCancellable)
  #expect(!request.isRetryable)
 }

 @Test func invalidUUIDIsRejected() {
  let dto = Components.Schemas.AiRequest(id: "not-a-uuid", conversationId: UUID().uuidString, createdAt: Date(), state: .queued)
  #expect(throws: DTOMapping.InvalidPayload.self) { try DTOMapping.request(dto) }
 }

 @Test func usageReportKeepsPeriodsApart() {
  let period = { (answers: Int, cost: Double) in
   Components.Schemas.UsagePeriod(answers: answers, inputTokens: 1000, cachedInputTokens: 250, outputTokens: 50, cost: cost)
  }
  let report = DTOMapping.usage(Components.Schemas.UsageReport(
   currency: "USD", timeZone: "Europe/Copenhagen", today: period(1, 0.01), month: period(5, 0.05), total: period(9, 0.09)
  ))
  #expect(report.today.answers == 1)
  #expect(report.month.cost == 0.05)
  #expect(report.total.answers == 9)
  #expect(report.today.cacheHitRate == 0.25)
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

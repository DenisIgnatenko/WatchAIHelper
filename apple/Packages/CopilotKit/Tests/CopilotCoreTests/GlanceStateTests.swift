import Foundation
import Testing
@testable import CopilotCore

/// Rules of the Watch complication (spec 40), tested without WidgetKit.
struct GlanceStateTests {

 private let now = Date(timeIntervalSince1970: 1_790_000_000)

 private func home(draft: DraftSummary = DraftSummary(id: UUID()), request: AIRequest.State? = nil,
  sentMinutesAgo: Double = 1) -> HomeSnapshot {
  let conversation = Conversation(id: UUID(), title: "Test", updatedAt: now)
  let latest = request.map {
   AIRequest(id: UUID(), conversationId: conversation.id, state: $0, createdAt: now.addingTimeInterval(-sentMinutesAgo * 60))
  }
  return HomeSnapshot(activeConversation: conversation, draft: draft, latestRequest: latest, lastAnswer: nil)
 }

 @Test func idleWithoutAnything() {
  #expect(GlanceState(home: home(), now: now) == .idle)
 }

 @Test func sendInProgressWinsOverDraftPhotos() {
  let draft = DraftSummary(id: UUID(), totalAttachments: 2, uploadedAttachments: 2)
  let state = GlanceState(home: home(draft: draft, request: .processing, sentMinutesAgo: 0.5), now: now)
  #expect(state == .processing(since: now.addingTimeInterval(-30)))
  #expect(state.isInProgress)
 }

 @Test func waitingSendShowsUploadProgress() {
  #expect(GlanceState(home: home(request: .waitingForAttachments(uploaded: 2, total: 3)), now: now)
   == .uploading(uploaded: 2, total: 3))
 }

 @Test func blockedSendOrFailedPhotoNeedsAttention() {
  #expect(GlanceState(home: home(request: .blocked(failedAttachments: 1)), now: now) == .needsAttention)
  let draft = DraftSummary(id: UUID(), totalAttachments: 2, uploadedAttachments: 1, failedAttachments: 1)
  #expect(GlanceState(home: home(draft: draft), now: now) == .needsAttention)
 }

 @Test func readyPhotosInTheDraft() {
  let draft = DraftSummary(id: UUID(), totalAttachments: 3, uploadedAttachments: 3)
  #expect(GlanceState(home: home(draft: draft, request: .completed(assistantMessageId: UUID())), now: now)
   == .photosReady(count: 3))
 }

 @Test func freshAnswerFadesAfterAnHour() {
  let fresh = GlanceState(home: home(request: .completed(assistantMessageId: UUID()), sentMinutesAgo: 10), now: now)
  #expect(fresh == .answerReady(sentAt: now.addingTimeInterval(-600)))
  #expect(fresh.expiresAt == now.addingTimeInterval(-600 + GlanceState.answerFreshness))
  let old = GlanceState(home: home(request: .completed(assistantMessageId: UUID()), sentMinutesAgo: 61), now: now)
  #expect(old == .idle)
 }

 @Test func failedAnswer() {
  #expect(GlanceState(home: home(request: .failed(reason: "x")), now: now) == .failed)
 }
}

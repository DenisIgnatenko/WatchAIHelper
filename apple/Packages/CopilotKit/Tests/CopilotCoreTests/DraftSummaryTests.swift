import Foundation
import Testing
@testable import CopilotCore

// Swift Testing notes: `@Test` marks a test function (like JUnit's @Test),
// `#expect(...)` is an assertion that reports the evaluated sub-expressions on failure.

struct DraftSummaryTests {

 @Test func noAttachments() {
  #expect(DraftSummary(id: UUID()).readiness == .noAttachments)
 }

 @Test func uploadingWhileSomeArePending() {
  let draft = DraftSummary(id: UUID(), totalAttachments: 3, uploadedAttachments: 2)
  #expect(draft.pendingAttachments == 1)
  #expect(draft.readiness == .uploading(uploaded: 2, total: 3))
 }

 @Test func readyWhenAllUploaded() {
  let draft = DraftSummary(id: UUID(), totalAttachments: 3, uploadedAttachments: 3)
  #expect(draft.readiness == .ready(count: 3))
 }

 @Test func failureWinsOverUploading() {
  // Invariant 6: a failed page must be visible even if others are still uploading.
  let draft = DraftSummary(id: UUID(), totalAttachments: 3, uploadedAttachments: 1, failedAttachments: 1)
  #expect(draft.readiness == .hasFailures(failed: 1))
 }
}

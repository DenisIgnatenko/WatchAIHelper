import CopilotCore

// Short, glanceable status strings (spec 36). Kept in one place so every screen says the same thing (DRY).

extension AIRequest.State {
 var statusText: String {
  switch self {
  case .waitingForAttachments(let uploaded, let total): "Uploading \(uploaded)/\(total)…"
  case .blocked(let failed): failed == 1 ? "1 photo failed" : "\(failed) photos failed"
  case .queued, .processing: "Processing…"
  case .completed: "Answer ready"
  case .failed(let reason): "Failed: \(reason)"
  case .cancelled: "Cancelled"
  }
 }
}

extension DraftSummary.Readiness {
 var statusText: String {
  switch self {
  case .noAttachments: ""
  case .uploading(let uploaded, let total): "Uploading \(uploaded)/\(total)…"
  case .ready(let count): count == 1 ? "1 photo ready" : "\(count) photos ready"
  case .hasFailures(let failed): failed == 1 ? "1 photo failed" : "\(failed) photos failed"
  }
 }
}

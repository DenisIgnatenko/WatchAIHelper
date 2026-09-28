import Foundation

/// Follows an AI request until it reaches a terminal state by long-polling the backend
/// (result-delivery strategy H1, docs/phase-0/platform-investigation.md section 9).
///
/// It is a concrete type on purpose. The architecture reserves other strategies
/// (background URLSession, APNs); a protocol will be extracted when the second implementation
/// actually appears, not before (YAGNI).
///
/// Swift notes:
/// - `AsyncThrowingStream` is a sequence of values delivered over time that can end with an error
///  (comparable to a reactive `Flux`). The UI consumes it with `for try await update in stream { ... }`.
public struct LongPollRequestObserver: Sendable {
 private let service: any CopilotService
 private let waitSeconds: Int
 private let retryDelay: Duration
 private let maxConsecutiveFailures: Int

 public init(
  service: any CopilotService,
  waitSeconds: Int = 25,
  retryDelay: Duration = .seconds(2),
  maxConsecutiveFailures: Int = 5
 ) {
  self.service = service
  self.waitSeconds = waitSeconds
  self.retryDelay = retryDelay
  self.maxConsecutiveFailures = maxConsecutiveFailures
 }

 /// Emits every state change of `request`, starting with its current state, and finishes after a terminal state.
 ///
 /// Transient network errors are retried (spec 43: "backend unavailable" must not lose the request -
 /// it keeps running on the backend anyway). After `maxConsecutiveFailures` the stream fails
 /// and the UI offers a manual refresh.
 public func updates(of request: AIRequest) -> AsyncThrowingStream<AIRequest, Error> {
  // Local copies: the closure below runs in a separate task and must capture only Sendable values.
  let service = service
  let waitSeconds = waitSeconds
  let retryDelay = retryDelay
  let maxFailures = maxConsecutiveFailures

  return AsyncThrowingStream { continuation in
   let task = Task {
    var current = request
    var failures = 0
    continuation.yield(current)
    while !current.state.isTerminal {
     do {
      let next = try await service.request(id: current.id, waitSeconds: waitSeconds)
      failures = 0
      if next != current {
       current = next
       continuation.yield(current)
      }
     } catch is CancellationError {
      break
     } catch {
      failures += 1
      if failures >= maxFailures {
       continuation.finish(throwing: error)
       return
      }
      try? await Task.sleep(for: retryDelay)
     }
    }
    continuation.finish()
   }
   // When the consumer stops listening (e.g. the screen disappears), stop polling.
   continuation.onTermination = { _ in task.cancel() }
  }
 }
}

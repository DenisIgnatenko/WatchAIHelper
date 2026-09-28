import Foundation

/// Uploads image files with a **background** URLSession (docs/phase-0/platform-investigation.md, section 10):
/// transfers continue in a system process while the app is suspended or the phone is locked (Invariant 7).
///
/// Limitation (documented by Apple): force-quitting the app from the app switcher cancels these transfers.
/// The backend then marks the image FAILED after its upload timeout, so a Send never proceeds without it.
///
/// Why a class with delegate callbacks instead of async/await: background sessions only support the
/// delegate API (the system may deliver the result to a relaunched app, long after the call returned).
///
/// Swift notes: `@unchecked Sendable` = "I guarantee thread safety myself". It holds here because the
/// properties are set once in `init` and never change; the delegate methods only forward events.
final class UploadManager: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, @unchecked Sendable {

 /// Stable identifier: after a relaunch the system reconnects finished/running transfers to this session.
 static let sessionIdentifier = "aicopilot.image-uploads"

 /// The one instance of the app. iOS allows only one session per identifier, and the app delegate must reach
 /// it even when the app is relaunched in the background without any UI. Set by the composition root.
 nonisolated(unsafe) static var shared: UploadManager?

 enum Event: Sendable {
  case progress(attachmentId: UUID, fraction: Double)
  case finished(attachmentId: UUID)
  case failed(attachmentId: UUID, reason: String)
 }

 private let baseURL: URL
 private let deviceToken: String
 private let onEvent: @Sendable (Event) -> Void
 /// Handed over by the app delegate when iOS relaunches the app for finished background transfers.
 private let backgroundCompletion = BackgroundCompletionBox()
 private var session: URLSession!

 init(baseURL: URL, deviceToken: String, onEvent: @escaping @Sendable (Event) -> Void) {
  self.baseURL = baseURL
  self.deviceToken = deviceToken
  self.onEvent = onEvent
  super.init()
  let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
  // Latency-sensitive: the user may press Send right away. Discretionary transfers could be postponed.
  configuration.isDiscretionary = false
  configuration.sessionSendsLaunchEvents = true
  session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
 }

 /// Starts (or restarts, for Retry) the upload of a prepared file. Idempotent on the backend.
 func upload(attachmentId: UUID, fileURL: URL) {
  var request = URLRequest(url: baseURL.appending(path: "v1/attachments/\(attachmentId.uuidString)/content"))
  request.httpMethod = "PUT"
  request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
  request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
  let task = session.uploadTask(with: request, fromFile: fileURL)
  // The attachment id travels with the task, so a relaunched app still knows what finished.
  task.taskDescription = attachmentId.uuidString
  task.resume()
 }

 func setBackgroundCompletion(_ handler: @escaping @Sendable () -> Void) {
  backgroundCompletion.set(handler)
 }

 // MARK: - URLSession delegate (called on a background queue)

 func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
  totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
  guard let id = attachmentId(of: task), totalBytesExpectedToSend > 0 else { return }
  onEvent(.progress(attachmentId: id, fraction: Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
 }

 func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
  guard let id = attachmentId(of: task) else { return }
  let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
  if error == nil, status == 200 {
   // Uploaded and verified by the backend: the local copy is no longer needed.
   try? FileManager.default.removeItem(at: ImageNormalizer.fileURL(for: id))
   onEvent(.finished(attachmentId: id))
  } else {
   onEvent(.failed(attachmentId: id, reason: error?.localizedDescription ?? "HTTP \(status)"))
  }
 }

 func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
  backgroundCompletion.callAndClear()
 }

 private func attachmentId(of task: URLSessionTask) -> UUID? {
  task.taskDescription.flatMap(UUID.init(uuidString:))
 }
}

/// Thread-safe holder of the system's completion handler for background session events.
private final class BackgroundCompletionBox: @unchecked Sendable {
 private let lock = NSLock()
 private var handler: (@Sendable () -> Void)?

 func set(_ handler: @escaping @Sendable () -> Void) {
  lock.withLock { self.handler = handler }
 }

 func callAndClear() {
  let handler = lock.withLock { () -> (@Sendable () -> Void)? in
   defer { self.handler = nil }
   return self.handler
  }
  // UIKit expects the handler on the main thread.
  if let handler { DispatchQueue.main.async { handler() } }
 }
}

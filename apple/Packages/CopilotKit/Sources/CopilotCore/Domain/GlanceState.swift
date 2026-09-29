import Foundation

/// What a glance (the Watch complication / Smart Stack, spec 40) shows: the one thing worth knowing
/// without opening the app. Derived from `HomeSnapshot` only, so the app and the widget extension
/// always agree (DRY), and the rules are unit-tested here instead of in a widget.
///
/// Priority (most urgent first):
/// 1. a Send in progress (uploading photos, processing, or blocked by a failed photo);
/// 2. photos in the draft (uploading, ready, failed) - the iPhone put them there, the Watch can Send;
/// 3. a fresh answer (for `answerFreshness` after Send);
/// 4. a failed answer;
/// 5. idle.
public enum GlanceState: Hashable, Sendable {
 case idle
 /// Photos on their way from the iPhone (in the draft or in a waiting Send).
 case uploading(uploaded: Int, total: Int)
 /// Photos ready in the draft; Send on the Watch.
 case photosReady(count: Int)
 /// A photo failed (draft or blocked Send): fix it on the iPhone.
 case needsAttention
 /// The AI is working on the question sent at `since`.
 case processing(since: Date)
 /// The answer to the question sent at `sentAt` is ready.
 case answerReady(sentAt: Date)
 /// The AI could not answer; Retry is on the main screen.
 case failed

 /// How long "answer ready" stays on the watch face after Send.
 public static let answerFreshness: TimeInterval = 60 * 60

 public init(home: HomeSnapshot, now: Date = Date()) {
  if let request = home.latestRequest, !request.state.isTerminal {
   switch request.state {
   case .waitingForAttachments(let uploaded, let total): self = .uploading(uploaded: uploaded, total: total)
   case .blocked: self = .needsAttention
   default: self = .processing(since: request.createdAt)
   }
   return
  }
  switch home.draft.readiness {
  case .uploading(let uploaded, let total):
   self = .uploading(uploaded: uploaded, total: total)
   return
  case .ready(let count):
   self = .photosReady(count: count)
   return
  case .hasFailures:
   self = .needsAttention
   return
  case .noAttachments:
   break
  }
  switch home.latestRequest?.state {
  case .completed? where now.timeIntervalSince(home.latestRequest!.createdAt) < Self.answerFreshness:
   self = .answerReady(sentAt: home.latestRequest!.createdAt)
  case .failed?:
   self = .failed
  default:
   self = .idle
  }
 }

 /// When this state turns into another one by itself (no backend change needed): "answer ready" fades to idle.
 /// The widget timeline schedules an entry for that moment.
 public var expiresAt: Date? {
  if case .answerReady(let sentAt) = self { return sentAt.addingTimeInterval(Self.answerFreshness) }
  return nil
 }

 /// Something is in progress on the backend or the iPhone, so the glance should be refreshed soon.
 public var isInProgress: Bool {
  switch self {
  case .uploading, .processing: true
  default: false
  }
 }
}

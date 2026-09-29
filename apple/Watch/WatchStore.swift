import CopilotCore
import Foundation
import Observation
import WidgetKit

/// Screens the Watch app can navigate to.
enum WatchRoute: Hashable {
 case conversation
 case history
 case inputLab
}

/// State and actions of the Watch app (the only "view model" of this small app).
///
/// Swift / SwiftUI notes:
/// - `@Observable` makes SwiftUI track which properties a view reads and re-render only those views
///  when they change. No manual "notify" calls (compare with Java property-change listeners).
/// - `@MainActor` = all code of this class runs on the main (UI) thread. SwiftUI requires UI state
///  to be changed there; the compiler enforces it, so no `runOnUiThread` style mistakes are possible.
/// - `private(set)` = readable by views, writable only here. Views change state only through methods (SRP).
///
/// What this class does NOT do: networking details (CopilotService), polling logic (LongPollRequestObserver),
/// haptics (injected closure). It only coordinates them for the UI.
@MainActor
@Observable
final class WatchStore {
 private(set) var home: HomeSnapshot?
 private(set) var messages: [Message] = []
 private(set) var conversations: [Conversation] = []
 /// The request the user is currently waiting for (drives "Uploading 2/3…", "Processing…").
 private(set) var activeRequest: AIRequest?
 /// Last error in user-readable form. `nil` = nothing to show.
 private(set) var errorText: String?
 /// Text of a Send that failed. Kept so user input is never silently lost (spec 43).
 private(set) var unsentText: String?
 /// Navigation stack of the app. `var` because NavigationStack writes to it when the user goes back.
 var path: [WatchRoute] = []

 private var service: any CopilotService
 private var observer: LongPollRequestObserver
 /// Mock-only debug tools (scenario switching) are shown only when running without a backend.
 var isUsingMock: Bool { service is MockCopilotService }
 private let onAnswerReady: @MainActor () -> Void
 /// The running observation; cancelled when a new request replaces it.
 private var observationTask: Task<Void, Never>?
 /// What the complication showed last time; the widget is reloaded only when this changes
 /// (WidgetKit has a daily reload budget, so no reload on every poll).
 private var glance: GlanceState?

 /// - Parameter onAnswerReady: called once per completed answer (the app plays a haptic there).
 init(service: any CopilotService, onAnswerReady: @escaping @MainActor () -> Void = {}) {
  self.service = service
  self.observer = LongPollRequestObserver(service: service)
  self.onAnswerReady = onAnswerReady
 }

 // MARK: - Loading

 /// Reloads the main-screen snapshot and the messages of the active conversation.
 func refresh() async {
  do {
   let snapshot = try await service.home()
   home = snapshot
   messages = try await service.messages(conversationId: snapshot.activeConversation.id)
   errorText = nil
   // A request may have been sent from the iPhone: follow it too, so its answer appears here
   // (with the haptic) without leaving and re-entering the screen.
   if let latest = snapshot.latestRequest, !latest.state.isTerminal, activeRequest?.id != latest.id {
    observe(latest)
   }
   updateComplication(GlanceState(home: snapshot))
  } catch {
   errorText = Self.describe(error)
  }
 }

 func loadConversations() async {
  do {
   conversations = try await service.conversations()
  } catch {
   errorText = Self.describe(error)
  }
 }

 /// How often the foreground app re-reads the state. Other devices change it without our actions
 /// (the iPhone adds photos or presses Send); there is no push (free account), so we poll while visible.
 /// One small request every few seconds only while the screen is on.
 var refreshInterval: Duration {
  if case .uploading = home?.draft.readiness { return .seconds(3) }
  return .seconds(4)
 }

 /// The request to show on the main screen: the one being followed, otherwise the latest of the conversation.
 /// A failed one stays visible (with Retry) after the app was relaunched.
 var visibleRequest: AIRequest? {
  activeRequest ?? home?.latestRequest
 }

 // MARK: - Actions

 /// Explicit Send (Invariant 5). Used for all three Watch cases:
 /// - text question (draft has no photos);
 /// - "Send" on a photo draft (`text == nil`);
 /// - "Add text & Send" on a photo draft (decision Q1: the text joins the photos).
 func send(text: String?) async {
  guard let draftId = home?.draft.id else { return }
  // One key per user action. If this very call is retried by the network layer later,
  // it reuses the same key and the backend returns the same request (spec 37).
  let idempotencyKey = UUID()
  do {
   let request = try await service.submit(draftId: draftId, text: text, idempotencyKey: idempotencyKey)
   unsentText = nil
   errorText = nil
   path = [.conversation]
   observe(request)
   await refresh()
  } catch {
   unsentText = text
   errorText = Self.describe(error)
   await refresh()
  }
 }

 /// Cancel Send while it still waits for photos (spec 26). The photos return to the draft card.
 func cancel(_ request: AIRequest) async {
  do {
   let cancelled = try await service.cancelRequest(id: request.id)
   observationTask?.cancel()
   activeRequest = cancelled
   errorText = nil
   await refresh()
  } catch {
   errorText = Self.describe(error)
   await refresh()
  }
 }

 /// Ask again after a failed answer: same question, no duplicate message.
 func retry(_ request: AIRequest) async {
  do {
   let queued = try await service.retryRequest(id: request.id)
   errorText = nil
   observe(queued)
  } catch {
   errorText = Self.describe(error)
  }
 }

 /// Irreversible; the view asks for confirmation first.
 func deleteConversation(_ conversation: Conversation) async {
  do {
   try await service.deleteConversation(id: conversation.id)
   conversations.removeAll { $0.id == conversation.id }
   if home?.activeConversation.id == conversation.id {
    observationTask?.cancel()
    activeRequest = nil
   }
   await refresh()
  } catch {
   errorText = Self.describe(error)
  }
 }

 func selectConversation(_ conversation: Conversation) async {
  do {
   try await service.setActiveConversation(id: conversation.id)
   activeRequest = nil
   await refresh()
   path = [.conversation]
  } catch {
   errorText = Self.describe(error)
  }
 }

 func createConversation(mode: ConversationMode) async {
  do {
   _ = try await service.createConversation(mode: mode)
   activeRequest = nil
   await refresh()
   path = []
  } catch {
   errorText = Self.describe(error)
  }
 }

 /// Phase 1 only: restart against a fresh mock with another draft scenario.
 func resetMock(scenario: MockCopilotService.DraftScenario) async {
  observationTask?.cancel()
  service = MockCopilotService(scenario: scenario)
  observer = LongPollRequestObserver(service: service)
  activeRequest = nil
  unsentText = nil
  path = []
  await refresh()
 }

 // MARK: - Request observation

 private func observe(_ request: AIRequest) {
  observationTask?.cancel()
  activeRequest = request
  // `Task { }` starts concurrent work that inherits the main actor, so assignments below are UI-safe.
  observationTask = Task { [observer] in
   do {
    for try await update in observer.updates(of: request) {
     activeRequest = update
     if case .completed = update.state {
      await refresh()
      onAnswerReady()
     }
    }
   } catch {
    errorText = "Connection lost. Pull to refresh."
   }
  }
 }

 // MARK: - Complication

 private func updateComplication(_ state: GlanceState) {
  guard state != glance else { return }
  glance = state
  WidgetCenter.shared.reloadAllTimelines()
 }

 // MARK: - Errors

 private static func describe(_ error: Error) -> String {
  switch error as? CopilotServiceError {
  case .draftAlreadySubmitted: "Already sent from another device."
  case .draftNotEditable: "Already sent."
  case .emptyDraft: "Nothing to send."
  case .notFound: "Not found."
  case .unauthorized: "Device not authorized."
  case .unavailable: "Server unavailable."
  case .requestNotCancellable: "Already sent to the AI."
  case .requestNotRetryable: "Ask the question again."
  case .invalidTitle: "Invalid title."
  case nil: "Something went wrong."
  }
 }
}

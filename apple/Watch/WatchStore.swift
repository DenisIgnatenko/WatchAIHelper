import CopilotCore
import Foundation
import Observation

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
 private let onAnswerReady: @MainActor () -> Void
 /// The running observation; cancelled when a new request replaces it.
 private var observationTask: Task<Void, Never>?

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

 func createConversation() async {
  do {
   _ = try await service.createConversation()
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

 // MARK: - Errors

 private static func describe(_ error: Error) -> String {
  switch error as? CopilotServiceError {
  case .draftAlreadySubmitted: "Already sent from another device."
  case .emptyDraft: "Nothing to send."
  case .notFound: "Not found."
  case .unavailable: "Server unavailable."
  case nil: "Something went wrong."
  }
 }
}

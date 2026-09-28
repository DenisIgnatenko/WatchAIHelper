import CopilotAPI
import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// `CopilotService` over HTTPS, using the client generated from api/openapi.yaml.
///
/// Responsibilities (SRP): call the backend, translate transport DTOs to domain models (DTOMapping.swift),
/// translate HTTP outcomes to `CopilotServiceError`. No UI state, no retry policy (that is the observer's job).
///
/// Swift notes:
/// - `struct` + only immutable (`let`) Sendable properties = safe to share between concurrent tasks without locks.
/// - The generated `Client` returns an enum per operation (`.ok`, `.notFound`, `.undocumented(...)`),
///  so every documented HTTP status must be handled explicitly - the compiler checks it with `switch`.
public struct LiveCopilotService: CopilotService {
 let client: Client

 /// - Parameters:
 ///  - baseURL: e.g. `https://203.0.113.10`.
 ///  - deviceToken: per-device bearer token (docs/architecture.md, section 17).
 public init(baseURL: URL, deviceToken: String) {
  let session = URLSession(configuration: {
   let configuration = URLSessionConfiguration.default
   // Long-poll waits up to 25 s on the server; leave headroom for the Watch -> iPhone -> internet hops.
   configuration.timeoutIntervalForRequest = 40
   configuration.waitsForConnectivity = false
   return configuration
  }())
  self.client = Client(
   serverURL: baseURL,
   configuration: .init(dateTranscoder: FlexibleISO8601DateTranscoder()),
   transport: URLSessionTransport(configuration: .init(session: session)),
   middlewares: [BearerTokenMiddleware(token: deviceToken)]
  )
 }

 public func home() async throws -> HomeSnapshot {
  switch try await call({ try await client.getHome() }) {
  case .ok(let ok): return try DTOMapping.home(ok.body.json)
  case .unauthorized: throw CopilotServiceError.unauthorized
  case .undocumented(let status, _): throw Self.error(forStatus: status)
  }
 }

 public func conversations() async throws -> [Conversation] {
  switch try await call({ try await client.listConversations() }) {
  case .ok(let ok): return try ok.body.json.map(DTOMapping.conversation)
  case .unauthorized: throw CopilotServiceError.unauthorized
  case .undocumented(let status, _): throw Self.error(forStatus: status)
  }
 }

 public func createConversation(mode: ConversationMode) async throws -> Conversation {
  // Client-generated id: a retried call cannot create a second conversation.
  let body = Components.Schemas.CreateConversationRequest(
   id: UUID().uuidString,
   mode: mode == .danishExam ? .danishExam : .general
  )
  switch try await call({ try await client.createConversation(body: .json(body)) }) {
  case .created(let created): return try DTOMapping.conversation(created.body.json)
  case .unauthorized: throw CopilotServiceError.unauthorized
  case .undocumented(let status, _): throw Self.error(forStatus: status)
  }
 }

 public func setActiveConversation(id: UUID) async throws {
  let body = Components.Schemas.SetActiveConversationRequest(conversationId: id.uuidString)
  switch try await call({ try await client.setActiveConversation(body: .json(body)) }) {
  case .noContent: return
  case .unauthorized: throw CopilotServiceError.unauthorized
  case .notFound: throw CopilotServiceError.notFound
  case .undocumented(let status, _): throw Self.error(forStatus: status)
  }
 }

 public func messages(conversationId: UUID) async throws -> [Message] {
  let output = try await call({
   try await client.listMessages(path: .init(conversationId: conversationId.uuidString))
  })
  switch output {
  case .ok(let ok): return try ok.body.json.map(DTOMapping.message)
  case .unauthorized: throw CopilotServiceError.unauthorized
  case .notFound: throw CopilotServiceError.notFound
  case .undocumented(let status, _): throw Self.error(forStatus: status)
  }
 }

 public func submit(draftId: UUID, text: String?, idempotencyKey: UUID) async throws -> AIRequest {
  let output = try await call({
   try await client.submitDraft(
    path: .init(draftId: draftId.uuidString),
    headers: .init(idempotencyKey: idempotencyKey.uuidString),
    body: .json(.init(text: text))
   )
  })
  switch output {
  case .accepted(let accepted): return try DTOMapping.request(accepted.body.json)
  case .conflict: throw CopilotServiceError.draftAlreadySubmitted
  case .unprocessableContent: throw CopilotServiceError.emptyDraft
  case .unauthorized: throw CopilotServiceError.unauthorized
  case .notFound: throw CopilotServiceError.notFound
  case .undocumented(let status, _): throw Self.error(forStatus: status)
  }
 }

 public func request(id: UUID, waitSeconds: Int) async throws -> AIRequest {
  let output = try await call({
   try await client.getRequest(path: .init(requestId: id.uuidString), query: .init(waitSeconds: waitSeconds))
  })
  switch output {
  case .ok(let ok): return try DTOMapping.request(ok.body.json)
  case .unauthorized: throw CopilotServiceError.unauthorized
  case .notFound: throw CopilotServiceError.notFound
  case .undocumented(let status, _): throw Self.error(forStatus: status)
  }
 }

 // MARK: - Error translation

 /// Runs a generated-client call and turns transport failures (offline, timeout, TLS) into `.unavailable`,
 /// so the UI deals with one error type. Task cancellation passes through unchanged.
 func call<Output>(_ operation: () async throws -> Output) async throws -> Output {
  do {
   return try await operation()
  } catch is CancellationError {
   throw CancellationError()
  } catch let error as CopilotServiceError {
   throw error
  } catch {
   throw CopilotServiceError.unavailable
  }
 }

 static func error(forStatus status: Int) -> CopilotServiceError {
  status == 404 ? .notFound : .unavailable
 }
}

/// Adds `Authorization: Bearer <token>` to every request.
/// Middleware = a hook around each HTTP call (like a servlet filter / OkHttp interceptor in Java).
struct BearerTokenMiddleware: ClientMiddleware {
 let token: String

 func intercept(
  _ request: HTTPRequest,
  body: HTTPBody?,
  baseURL: URL,
  operationID: String,
  next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
 ) async throws -> (HTTPResponse, HTTPBody?) {
  var request = request
  request.headerFields[.authorization] = "Bearer \(token)"
  return try await next(request, body, baseURL)
 }
}

/// Accepts ISO-8601 timestamps with and without fractional seconds.
/// The Java backend writes `2026-09-28T14:59:37.685246Z`, but omits the fraction when it is zero.
struct FlexibleISO8601DateTranscoder: DateTranscoder {
 private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
 private static let withoutFraction = Date.ISO8601FormatStyle()

 func encode(_ date: Date) throws -> String {
  Self.withFraction.format(date)
 }

 func decode(_ string: String) throws -> Date {
  if let date = try? Self.withFraction.parse(string) { return date }
  return try Self.withoutFraction.parse(string)
 }
}

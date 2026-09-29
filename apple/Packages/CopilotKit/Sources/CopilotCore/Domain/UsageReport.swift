import Foundation

/// AI token usage and its estimated cost (backend `GET /v1/usage`).
///
/// The cost is an estimate: the backend multiplies token counts by the configured price list.
public struct UsageReport: Hashable, Sendable {
 /// ISO 4217 code, e.g. "USD".
 public let currency: String
 /// IANA time zone that defines "today" and "this month".
 public let timeZone: String
 public let today: Period
 public let month: Period
 public let total: Period

 public init(currency: String, timeZone: String, today: Period, month: Period, total: Period) {
  self.currency = currency
  self.timeZone = timeZone
  self.today = today
  self.month = month
  self.total = total
 }

 public struct Period: Hashable, Sendable {
  /// Number of AI answers.
  public let answers: Int
  /// All input tokens, cached ones included.
  public let inputTokens: Int64
  public let cachedInputTokens: Int64
  public let outputTokens: Int64
  public let cost: Double

  public init(answers: Int, inputTokens: Int64, cachedInputTokens: Int64, outputTokens: Int64, cost: Double) {
   self.answers = answers
   self.inputTokens = inputTokens
   self.cachedInputTokens = cachedInputTokens
   self.outputTokens = outputTokens
   self.cost = cost
  }

  /// Share of input served from the prompt cache (0...1): the higher, the cheaper and faster.
  public var cacheHitRate: Double {
   inputTokens > 0 ? Double(cachedInputTokens) / Double(inputTokens) : 0
  }
 }
}

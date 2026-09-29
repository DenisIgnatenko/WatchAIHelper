import CopilotAPI
import Foundation

/// iPhone-only spending report over HTTPS (see `UsageReportingService`).
extension LiveCopilotService: UsageReportingService {

 public func usage() async throws -> UsageReport {
  switch try await call({ try await client.getUsage() }) {
  case .ok(let ok): return DTOMapping.usage(try ok.body.json)
  case .unauthorized: throw CopilotServiceError.unauthorized
  case .undocumented(let status, _): throw Self.error(forStatus: status)
  }
 }
}

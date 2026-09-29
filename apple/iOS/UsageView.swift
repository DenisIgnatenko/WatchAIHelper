import CopilotCore
import SwiftUI

/// AI spending control: estimated cost and tokens for today, this month and all time.
///
/// The numbers are an estimate: the backend multiplies token counts by the configured price list
/// (OpenAI bills the real amount). Deleted conversations still count here: privacy removes the content,
/// not the spending history.
struct UsageView: View {
 @Environment(DraftStore.self) private var store
 @State private var report: UsageReport?
 @State private var errorText: String?

 var body: some View {
  List {
   if let report {
    Section {
     PeriodRow(title: "Today", period: report.today, currency: report.currency)
     PeriodRow(title: "This month", period: report.month, currency: report.currency)
     PeriodRow(title: "All time", period: report.total, currency: report.currency)
    } footer: {
     Text("Estimated from token counts and the price list configured on the server. Days and months in \(report.timeZone).")
    }
    Section("This month in detail") {
     LabeledContent("Input tokens", value: report.month.inputTokens.formatted())
     LabeledContent("From the prompt cache", value: report.month.cacheHitRate.formatted(.percent.precision(.fractionLength(0))))
     LabeledContent("Output tokens", value: report.month.outputTokens.formatted())
    }
   } else if let errorText {
    Text(errorText).foregroundStyle(.red)
   } else {
    ProgressView()
   }
  }
  .navigationTitle("AI costs")
  .task { await load() }
  .refreshable { await load() }
 }

 private func load() async {
  do {
   report = try await store.service.usage()
   errorText = nil
  } catch {
   errorText = "Could not load the report."
  }
 }
}

private struct PeriodRow: View {
 let title: String
 let period: UsageReport.Period
 let currency: String

 var body: some View {
  HStack {
   VStack(alignment: .leading, spacing: 2) {
    Text(title)
    Text(period.answers == 1 ? "1 answer" : "\(period.answers) answers")
     .font(.caption)
     .foregroundStyle(.secondary)
   }
   Spacer()
   // Small amounts need more digits: $0.0042 is more useful than $0.00.
   Text(period.cost, format: .currency(code: currency).precision(.fractionLength(period.cost < 1 ? 4 : 2)))
    .font(.title3.monospacedDigit())
  }
 }
}

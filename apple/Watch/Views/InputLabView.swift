import SwiftUI

/// Diagnostic screen for device checks V1-V3 (docs/phase-0/platform-investigation.md, section 14):
/// shows exactly what the system text input produced, including Unicode code points,
/// so Russian (Cyrillic), Danish (æ ø å) and English input can be verified on the real watch.
///
/// Phase 1 only. Remove when the checks are done (YAGNI).
struct InputLabView: View {
 /// Local UI state: belongs to this screen only, so `@State` (not the shared store).
 @State private var text = ""

 var body: some View {
  List {
   TextFieldLink(prompt: Text("Type or dictate")) {
    Label("Enter text", systemImage: "keyboard")
   } onSubmit: { value in
    text = value
   }

   if !text.isEmpty {
    Section("Result") {
     Text(text)
     Text("Characters: \(text.count) · Scalars: \(text.unicodeScalars.count)")
      .font(.footnote)
     // NFC check: the backend will compare strings byte-wise, so we want a stable normalization.
     Text(text == text.precomposedStringWithCanonicalMapping ? "NFC: yes" : "NFC: no")
      .font(.footnote)
    }
    Section("Code points") {
     // Show non-ASCII scalars only: those are the ones that can get corrupted.
     ForEach(Array(text.unicodeScalars.filter { !$0.isASCII }.enumerated()), id: \.offset) { _, scalar in
      Text("\(String(scalar))  U+\(String(scalar.value, radix: 16, uppercase: true))")
       .font(.system(.footnote, design: .monospaced))
     }
    }
   }
  }
  .compactList()
  .navigationTitle("Input test")
 }
}

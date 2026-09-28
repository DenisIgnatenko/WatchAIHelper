import SwiftUI

// Compact visual style for the 49 mm Ultra display.
//
// watchOS defaults (about 44 pt rows, body font, capsule background per row) show only ~2.5 rows
// on the Ultra screen - too few for a glanceable main screen. All sizing lives here, so every screen
// looks the same and future tuning is a one-place change (DRY).
//
// Text sizes were reduced at the owner's request after trying the app on the Ultra 2.

enum CompactStyle {
 /// Minimum list row height. Default is ~44 pt.
 static let rowHeight: CGFloat = 30
 /// Font of button titles and secondary rows.
 static let controlFont: Font = .footnote
 /// Font of message text in the conversation and of the answer preview.
 static let messageFont: Font = .footnote
 /// Inner padding of list rows.
 static let rowInsets = EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8)
 /// App accent color: primary actions (Send). Without it, prominent buttons render grey.
 static let accent: Color = .blue
 /// Size of buttons placed side by side inside one row.
 static let inlineButtonSize: ControlSize = .mini
}

extension View {
 /// Applies the compact style to a whole `List`.
 ///
 /// SwiftUI "environment" values flow down the view tree: setting them on the List
 /// affects every row inside it (similar to inherited CSS properties).
 func compactList() -> some View {
  self
   .environment(\.defaultMinListRowHeight, CompactStyle.rowHeight)
   .controlSize(.small)
   .font(CompactStyle.controlFont)
 }

 /// A list row with reduced padding.
 func compactRow() -> some View {
  listRowInsets(CompactStyle.rowInsets)
 }

 /// A list row that shows information, not an action: no button-like background.
 func infoRow() -> some View {
  self
   .listRowBackground(Color.clear)
   .listRowInsets(CompactStyle.rowInsets)
 }
}

// swift-tools-version: 6.2
//
// CopilotKit - code shared by the iOS app and the watchOS app.
//
// Why a local Swift package instead of files added to both app targets:
// - one compiled module, imported with `import CopilotCore` from both apps (DRY);
// - it can be unit-tested on the Mac with `swift test`, without a simulator;
// - the compiler enforces the boundary: the package cannot see app/UI code.
//
// Modules:
// - CopilotCore: domain models, service contract, mock service, request observation.
// - CopilotAPI (Phase 2): client generated from api/openapi.yaml. Not created yet (YAGNI).

import PackageDescription

let package = Package(
 name: "CopilotKit",
 platforms: [
  .iOS("27.0"),
  .watchOS("27.0"),
  // macOS is listed only so that `swift test` can run the tests on the development Mac.
  .macOS("27.0"),
 ],
 products: [
  .library(name: "CopilotCore", targets: ["CopilotCore"]),
 ],
 targets: [
  .target(
   name: "CopilotCore",
   swiftSettings: [
    // Swift 6 language mode: full data-race safety checking at compile time.
    .swiftLanguageMode(.v6),
   ]
  ),
  .testTarget(
   name: "CopilotCoreTests",
   dependencies: ["CopilotCore"],
   swiftSettings: [.swiftLanguageMode(.v6)]
  ),
 ]
)

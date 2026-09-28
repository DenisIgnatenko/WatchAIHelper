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
// - CopilotAPI: HTTP client + transport DTOs GENERATED from api/openapi.yaml (scripts/generate-api.sh)
//  (the same contract the Java backend is generated from, so client and server cannot drift).
// - CopilotCore: domain models, service contract, live (HTTP) and mock services, request observation.
//  Only CopilotCore sees the generated DTOs; the apps see domain models (spec 52).

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
 dependencies: [
  // Apple's OpenAPI tooling: build plugin (generator), runtime types and a URLSession transport.
  .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.13.1"),
  .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.12.1"),
  .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.3.1"),
 ],
 targets: [
  .target(
   name: "CopilotAPI",
   dependencies: [
    .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
   ],
   // Generated sources are committed (Sources/CopilotAPI/GeneratedSources) and refreshed with
   // apple/scripts/generate-api.sh. A build plugin is not used: Xcode runs it once per platform
   // (iOS + embedded watchOS app) into the same folder and fails with "Multiple commands produce".
   // Generator inputs live next to the output but are not compiled or bundled.
   exclude: ["openapi.yaml", "openapi-generator-config.yaml"],
   swiftSettings: [.swiftLanguageMode(.v6)]
  ),
  .target(
   name: "CopilotCore",
   dependencies: [
    "CopilotAPI",
    .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
    .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
   ],
   swiftSettings: [
    // Swift 6 language mode: full data-race safety checking at compile time.
    .swiftLanguageMode(.v6),
   ]
  ),
  .testTarget(
   name: "CopilotCoreTests",
   dependencies: ["CopilotCore", "CopilotAPI"],
   swiftSettings: [.swiftLanguageMode(.v6)]
  ),
 ]
)

# Phase 0 - Platform Investigation

Status: complete (documentation review). Device validation items are listed in section 14.
Date: 2026-09-28.
Toolchain on the development Mac: macOS 27.0, Xcode 27.0 (27A266a).
Target hardware: iPhone 17 Pro Max (iOS 27), Apple Watch Ultra 2 (watchOS 27, no cellular plan).
Signing: free Apple Developer account (Personal Team). No paid Apple Developer Program membership.

## How to read this document

Every finding is labelled:

- **VERIFIED (docs)** - confirmed in official Apple / OpenAI documentation on the date above. Source linked.
- **VERIFIED (device)** - confirmed on the real hardware. Filled in during Phase 1+.
- **UNVERIFIED** - widely reported or inferred, but not confirmed in official documentation. Must be validated before we depend on it.
- **PROPOSAL** - our design decision built on top of the findings. Not a platform fact.

No Apple API is assumed to exist unless it is linked below.

---

## 1. Apple account and signing (free Personal Team)

| # | Finding | Status | Source |
|---|---|---|---|
| 1.1 | Free "Apple Developer" accounts can use: App Groups, Background Modes, Data Protection, Keychain Sharing, HealthKit, HomeKit, Maps. | VERIFIED (docs) | [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios) |
| 1.2 | Free accounts **cannot** use: **Push Notifications**, **Time Sensitive Notifications**, **Siri** (SiriKit entitlement), Associated Domains, iCloud/CloudKit, App Attest, Sign in with Apple, Communication Notifications. | VERIFIED (docs) | same |
| 1.3 | Free accounts cannot distribute apps (no TestFlight, no App Store). | VERIFIED (docs) | same |
| 1.4 | Provisioning profiles of a Personal Team expire after 7 days; the app stops launching until it is rebuilt and reinstalled from Xcode. | UNVERIFIED (well known, not found on an official page) | - |
| 1.5 | Personal Team limits: about 3 installed apps per device and 10 App IDs per 7 days. | UNVERIFIED | - |
| 1.6 | App Intents / App Shortcuts do not require the SiriKit "Siri" entitlement, so they should work with a Personal Team. | UNVERIFIED - validate in Phase 1 | - |

**Consequences**

- No APNs. The backend cannot wake the Watch or the iPhone. See section 9 for the replacement strategy.
- The iOS app, the Watch app and any future extension each consume an App ID. Keep the number of extensions minimal (YAGNI).
- Supporting other users in the future (a stated goal) requires a paid membership (TestFlight). The architecture keeps this door open (see `docs/architecture.md`, section "Multi-user readiness").

## 2. iPhone Action Button and App Intents (iOS 27)

| # | Finding | Status | Source |
|---|---|---|---|
| 2.1 | `AppShortcutsProvider` and `OpenIntent` exist on iOS 16+ and watchOS 9+. An App Shortcut can be assigned to the iPhone Action Button. | VERIFIED (docs) for the API; Action Button assignment UNVERIFIED on iOS 27 | [AppShortcutsProvider](https://developer.apple.com/documentation/appintents/appshortcutsprovider), [OpenIntent](https://developer.apple.com/documentation/appintents/openintent) |
| 2.2 | iOS 27 App Intents additions: `LongRunningIntent`, `CancellableIntent`, `ExecutionTargets`, `SyncableEntity`, `EntityCollection`, `@UnionValue`. None of them concern the Action Button or the camera. | VERIFIED (docs) | [WWDC26: Discover new capabilities in the App Intents framework](https://developer.apple.com/videos/play/wwdc2026/345/) |
| 2.4 | On the owner's iPhone (Personal Team signing) the app's App Shortcut does **not** appear in Shortcuts > App Shortcuts, although the build contains correct App Intents metadata (`autoShortcuts: AskWithCameraIntent`) and the app was launched. Cause unknown; possibly related to the missing Siri capability of free accounts (1.2). | VERIFIED (device), 2026-09-28; cause UNVERIFIED | - |
| 2.5 | iOS Controls (`ControlWidget`, iOS 18+) can be assigned to the iPhone Action Button and launch a capture extension (see 3.1). | VERIFIED (docs) | [StaticControlConfiguration](https://developer.apple.com/documentation/widgetkit/staticcontrolconfiguration), same as 3.1 |
| 2.3 | SiriKit is deprecated in iOS 27. App Intents is the only way to integrate with the new Siri. | UNVERIFIED (third-party WWDC26 coverage) | - |

**DECISION (revised after 2.4).** "Ask with Camera" is an intent that opens the app directly on the camera screen, exposed as a **Control** (`AICopilotWidgets` extension) that the user assigns via Settings > Action Button > Controls. The App Shortcut is kept for Siri/Spotlight. Unlocking through Face ID is part of the flow.

## 3. Lock Screen camera (LockedCameraCapture) - faster alternative, deferred

| # | Finding | Status | Source |
|---|---|---|---|
| 3.1 | A Locked Camera Capture Extension can be launched from a Control (Control Center, Lock Screen) **or from the Action button** while the device is locked. | VERIFIED (docs) | [Creating a camera experience for the Lock Screen](https://developer.apple.com/documentation/lockedcameracapture/creating-a-camera-experience-for-the-lock-screen) |
| 3.2 | While active, the extension **cannot access the network** and **cannot read or write the App Group container**. | VERIFIED (docs) | same |
| 3.3 | The extension must show an active camera view using `AVCaptureEventInteraction`, otherwise the system terminates it. | VERIFIED (docs) | same |
| 3.4 | Captured content is stored in `sessionContentURL`. After unlock, the containing app reads it through `LockedCameraCaptureManager.shared.sessionContentURLs` / `sessionContentUpdates` and releases it with `invalidateSessionContent(at:)`. | VERIFIED (docs) | [LockedCameraCaptureManager](https://developer.apple.com/documentation/lockedcameracapture/lockedcameracapturemanager) |
| 3.5 | The extension requires a WidgetKit Control and a `CameraCaptureIntent`, which means extra targets (App IDs). | VERIFIED (docs) | same |

**Limitation.** Pages captured while the phone is locked **cannot start uploading** until the user unlocks the iPhone and the app processes the content. This conflicts with preemptive upload (spec section 24) and with "put the iPhone away".

**PROPOSAL.** Not in MVP. Re-evaluate in Phase 6 when we have real timing measurements: extension (no unlock, no upload while locked) vs App Shortcut (Face ID unlock, upload starts immediately).

## 4. Camera capture

| # | Finding | Status | Source |
|---|---|---|---|
| 4.1 | `VNDocumentCameraViewController` (VisionKit, iOS 13+) scans multiple pages with edge detection and perspective correction. All pages are returned **only when the user finishes the session**. | VERIFIED (docs) for availability; batch-return behaviour is documented API design | [VNDocumentCameraViewController](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller) |
| 4.2 | `AVCaptureEventInteraction` lets a camera view react to hardware buttons (volume, Camera Control, Action button) as a shutter. | VERIFIED (docs, referenced from 3.3) | same as 3.1 |
| 4.3 | Custom AVFoundation capture (`AVCaptureSession` + `AVCapturePhotoOutput`) gives full control over the confirm step and per-page upload start. | VERIFIED (general AVFoundation API) | - |

**PROPOSAL.** A custom AVFoundation camera screen:
`capture -> inline preview [Retake] [Use] -> Use adds the page to the draft, starts the upload, and returns to the viewfinder instantly`.
This is the only option that satisfies both "confirm each photo" (spec 18) and "upload starts immediately" (spec 24).
VisionKit's scanner is kept as a Phase 6 experiment: better image quality for documents, but no preemptive upload.

## 5. Photo Library

| # | Finding | Status | Source |
|---|---|---|---|
| 5.1 | SwiftUI `PhotosPicker` (iOS 16+) supports single and multiple selection. It runs out of process, so **no photo-library permission prompt is needed**. | VERIFIED (docs) | [PhotosPicker](https://developer.apple.com/documentation/photosui/photospicker) |
| 5.2 | `PhotosPickerSelectionBehavior.ordered` "uses the selection order the user made, numbering the selected items". This preserves page order (spec 27). | VERIFIED (docs) | [PhotosPickerSelectionBehavior](https://developer.apple.com/documentation/photosui/photospickerselectionbehavior) |
| 5.3 | Results are `PhotosPickerItem` placeholders. Loading data may fail, for example for iCloud Photos without a network connection. | VERIFIED (docs) | same as 5.1 |

## 6. Text input on Apple Watch (watchOS 27)

| # | Finding | Status | Source |
|---|---|---|---|
| 6.1 | Available input methods: dictation, Scribble, onscreen keyboard, emoji, **and continuing input on the paired iPhone** ("Apple Watch Keyboard Input" notification). A Bluetooth keyboard is also supported. | VERIFIED (docs) | [Enter text on Apple Watch](https://support.apple.com/guide/watch/enter-text-apdaf7837856/watchos) |
| 6.2 | watchOS feature availability: **Russian and Danish are listed** for keyboard language support, QuickPath, Autocorrection and (server) Dictation. | VERIFIED (docs) | [watchOS Feature Availability](https://www.apple.com/watchos/feature-availability/) |
| 6.3 | **Russian and Danish are NOT listed for Scribble** and not listed for On-device Dictation. On-device dictation is irrelevant for us because the Watch always needs the network to reach the backend anyway. | VERIFIED (docs) | same |
| 6.4 | Keyboards of several languages can be enabled; the user switches by swiping up from the bottom of the keyboard. | VERIFIED (docs) | same as 6.1 |
| 6.5 | `TextFieldLink` (watchOS 9+): "a control that requests text input from the user when pressed". It gives a one-tap "Ask" button that opens system text input. | VERIFIED (docs) | [TextFieldLink](https://developer.apple.com/documentation/swiftui/textfieldlink) |
| 6.6 | Older sources (watchOS 11 era) state that there is no Russian or Danish keyboard on the Watch. This contradicts 6.2 and is treated as outdated. | Superseded by 6.2 | - |

**PROPOSAL.** No custom keyboard (spec 14). Use `TextFieldLink` / `TextField`, which delegate to the system input UI.
**Device validation required** (section 14): the Russian and Danish keyboards must be added on the Watch in Settings > General > Keyboard. Dictation of mixed-language phrases also needs testing.

## 7. Apple Watch Ultra Action Button

| # | Finding | Status | Source |
|---|---|---|---|
| 7.1 | Third-party apps appear in Settings > Action Button **only as workout apps (`StartWorkoutIntent`) or dive apps (`StartDiveIntent`)**. | VERIFIED (docs) | [Responding to the Action button on Apple Watch Ultra](https://developer.apple.com/documentation/appintents/actionbuttonarticle) |
| 7.2 | Built-in Action Button options include **"Shortcut"**, which runs a shortcut from the Shortcuts app. | VERIFIED (docs) | same, and [Use the Action button](https://support.apple.com/guide/watch/use-the-action-button-apda005904ef/watchos) (watchOS 27) |
| 7.3 | "Controls are available on Apple Watch starting in watchOS 26. People can place your controls in the Control Center, the Smart Stack, and **use them with the Action button on Apple Watch Ultra**." Watch-app controls run their action on the watch. | VERIFIED (docs) | [WWDC25: What's new in watchOS 26](https://developer.apple.com/videos/play/wwdc2025/334/), [StaticControlConfiguration](https://developer.apple.com/documentation/widgetkit/staticcontrolconfiguration) (watchOS 26.0+) |
| 7.4 | A watch app's App Shortcut ("Ask AI") is visible in Shortcuts on the watch but **cannot be selected** in Settings > Action Button > Shortcut, and the iPhone Shortcuts app cannot build a shortcut with it (the intent exists only in the watch app). | VERIFIED (device), 2026-09-28 | - |

**DECISION (revised after 7.4).** The Action Button route is a **watchOS Control** "Ask AI" in a widget extension (`AICopilotWatchWidgets`), which opens the app. Supported API, not a workout/dive workaround (spec 41). The App Shortcut remains for Siri/Spotlight.
Pending device check V6: the Control is selectable for the Action Button and opens the app.

## 8. Watch networking and iPhone <-> Watch synchronization

| # | Finding | Status | Source |
|---|---|---|---|
| 8.1 | A watchOS app calls web services directly with `URLSession`. The system routes traffic through the paired iPhone (Bluetooth), a known Wi-Fi network, or cellular. The app code is the same for all routes. | VERIFIED (docs) | [Keeping your watchOS app's content up to date](https://developer.apple.com/documentation/watchos-apps/keeping-your-watchos-app-s-content-up-to-date) |
| 8.2 | Apple: WatchConnectivity "isn't always available" and must be used "as an opportunistic optimization, rather than the primary means of supplying fresh data". | VERIFIED (docs) | same |
| 8.3 | WatchConnectivity transfers small data or files between the iOS app and the watchOS app; most transfers happen in the background. | VERIFIED (docs) | [WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity) |
| 8.4 | Foreground requests should use default/ephemeral sessions (lowest latency). Background sessions guarantee eventual delivery but may be delayed by the system. | VERIFIED (docs) | same as 8.1 |

Without a cellular plan, the Watch reaches the backend through the iPhone or known Wi-Fi. This matches the requirement "the phone is nearby".

**PROPOSAL.** The backend is the single source of truth; both clients poll it over HTTPS (spec 38). WatchConnectivity is used only for one-time provisioning of the device token from iPhone to Watch.

## 9. Result delivery to the Watch without push

| # | Finding | Status | Source |
|---|---|---|---|
| 9.1 | Background app refresh on watchOS runs only if the app **has a complication on the active watch face**. The system may defer or throttle tasks, and apps get "a few seconds" of execution time. | VERIFIED (docs) | [Using background tasks](https://developer.apple.com/documentation/watchkit/using-background-tasks) |
| 9.2 | A completed **background `URLSession` transfer wakes the watchOS app** (`WKURLSessionRefreshBackgroundTask` / SwiftUI `.backgroundTask(.urlSession)`), but the system may defer background sessions. | VERIFIED (docs) | [WKURLSessionRefreshBackgroundTask](https://developer.apple.com/documentation/watchkit/wkurlsessionrefreshbackgroundtask), [Using background tasks](https://developer.apple.com/documentation/watchkit/using-background-tasks) |
| 9.3 | `WKInterfaceDevice.play(_:)` plays haptic feedback. | VERIFIED (docs) | [play(_:)](https://developer.apple.com/documentation/watchkit/wkinterfacedevice/play(_:)) |
| 9.4 | Local notifications need no push entitlement. Notifications from a locked iPhone are mirrored to the Watch. | UNVERIFIED for our exact flow | - |
| 9.5 | "Return to Clock" can be set per app (for example, 1 hour) so our app stays frontmost when the wrist is raised. | UNVERIFIED on watchOS 27 | - |

**PROPOSAL - three supported strategies, validated in Phase 2:**

- **H1 (baseline).** After Send, the Watch app stays frontmost and long-polls `GET /requests/{id}?waitSeconds=25`. When the answer arrives it plays a haptic and renders it. Risk: while the wrist is down, the app may be suspended; the haptic then fires only when the wrist is raised.
- **H2.** The Watch issues the long-poll as a background `URLSession` download. On completion the system wakes the app, which posts a local notification or plays a haptic. Risk: the system may delay the transfer.
- **H3.** The iPhone does the same with a background `URLSession`; on completion it posts a local notification, which is mirrored to the Watch while the iPhone is locked. Risk: delays and mirroring rules.

No workout/extended-runtime-session workaround (spec 41).
The client code hides this behind one abstraction, so APNs can be added later without touching the UI (Open/Closed).

## 10. Background uploads on iOS

| # | Finding | Status | Source |
|---|---|---|---|
| 10.1 | `URLSessionConfiguration.background(withIdentifier:)` hands transfers to a system process; they continue while the app is suspended or terminated by the system. | VERIFIED (docs) | [background(withIdentifier:)](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:)) |
| 10.2 | **If the user force-quits the app from the app switcher, all background transfers are cancelled** and the app is not relaunched automatically. | VERIFIED (docs) | same |
| 10.3 | `isDiscretionary = true` lets the system postpone transfers; it must be `false` for our latency-sensitive uploads. | VERIFIED (docs) | same |
| 10.4 | `uploadTask(with:fromFile:)` uploads a file as the HTTP body. Background sessions only support uploads from a file. | VERIFIED (docs) for the API; file-only restriction is a known Foundation constraint | [uploadTask(with:fromFile:)](https://developer.apple.com/documentation/foundation/urlsession/uploadtask(with:fromfile:)) |

**Consequences / PROPOSAL**

- Upload body = raw image file (JPEG), not multipart. This is the simplest body a background session supports.
- The backend must detect uploads that never arrive (for example after a force-quit): stale `PENDING` attachments become `FAILED` after a configurable timeout, so a submission never waits forever and never proceeds silently (Invariant 6).

## 11. OpenAI Responses API

| # | Finding | Status | Source |
|---|---|---|---|
| 11.1 | Images are passed as `input_image` items in the `content` array: `image_url` (URL or `data:image/...;base64,` URL) or `file_id`. | VERIFIED (docs) | [Images and vision](https://developers.openai.com/api/docs/guides/images-vision) |
| 11.2 | Multiple images per request are supported by adding several `input_image` items. Limits: **up to 1,500 images and 512 MB total payload per request**; formats PNG, JPEG, WEBP, non-animated GIF. | VERIFIED (docs) | same |
| 11.3 | `detail`: `low`, `high`, `original`, `auto` (model dependent). For OCR-like tasks the docs recommend `original` when supported. Images count as input tokens. | VERIFIED (docs) | same |
| 11.4 | Current flagship models: `gpt-6-astra` (most capable), `gpt-6-sol` (balance), `gpt-6-luna` (cost/volume). All support text and image input. | VERIFIED (docs) | [Models](https://developers.openai.com/api/docs/models) |
| 11.5 | Multi-turn state options: (a) replay history manually with `store: false`, (b) `previous_response_id` with `store: true`, (c) the Conversations API. For stateless reasoning requests the full `output` array (including encrypted reasoning items) should be replayed. | VERIFIED (docs) | [Conversation state](https://developers.openai.com/api/docs/guides/conversation-state) |
| 11.6 | API data is not used for training by default. `/v1/responses`: abuse-monitoring retention **30 days**, application state "None" (with exceptions). `/v1/conversations`: stored **until deleted**. Zero Data Retention requires prior approval by OpenAI. Image inputs are scanned for CSAM. | VERIFIED (docs) | [Your data](https://developers.openai.com/api/docs/guides/your-data) |
| 11.7 | Structured Outputs: `text.format` with `type: "json_schema"`, `strict: true`. Safety refusals are programmatically detectable. | VERIFIED (docs) | [Structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs) |
| 11.8 | Official Java SDK `openai-java` (latest v4.69.3, 2026-09-25) supports the Responses API, structured outputs (including from Java classes), retries and timeouts. | VERIFIED (docs) | [openai-java](https://github.com/openai/openai-java) |

**PROPOSAL.** `store: false`, backend-built context (source of truth, spec 32/38), images sent as base64 data URLs, structured output schema `{text, suggestedActions[]}`, model from configuration. Details in `docs/architecture.md`, section 15.

## 12. Tooling versions (checked 2026-09-28)

| Tool | Version | Source |
|---|---|---|
| Spring Boot | 4.1.1 | GitHub releases |
| springdoc-openapi | 3.1.1 | GitHub releases |
| openai-java | 4.69.3 | GitHub releases |
| swift-openapi-generator | 1.13.1 | GitHub releases |
| Java | 25 (current LTS) | - |

## 13. Platform limitations summary

1. **No push** (free account). Result delivery relies on H1/H2/H3 (section 9). The haptic while the wrist is down is not guaranteed.
2. **7-day reinstall** from Xcode (free account).
3. **Force-quitting the iPhone app cancels uploads.** The backend turns stale uploads into `FAILED`; the user sees Retry/Remove.
4. **No Scribble for Russian/Danish**; keyboard and dictation are available.
5. **The Watch Action Button** can only be used through a user-created Shortcut.
6. **The Lock Screen camera extension cannot upload** while the device is locked. Deferred.
7. **Watch background refresh** needs a complication on the active face and is throttled. Not relied upon.

## 14. Device validation checklist (owner of each item: the user, with a test build from Phase 1)

- [ ] V1. Watch: add the Russian and Danish keyboards (Watch app on iPhone > General > Keyboards). Type "Почему здесь Redis?", "Hvad betyder selvom?", "why kafka?" and check that the Unicode round-trip is correct.
- [ ] V2. Watch: dictate the same phrases in each language.
- [ ] V3. Watch: continue input on the iPhone ("Apple Watch Keyboard Input").
- [ ] V4. A Personal-Team-signed app installs on both devices; note the profile expiry date.
- [x] V5a. The iOS App Shortcut in Shortcuts / Action Button > Shortcut: **not listed** (2.4).
- [ ] V5b. The "Ask with Camera" Control can be assigned to the iPhone Action Button and opens the app.
- [x] V6a. The watchOS App Shortcut via Action Button > Shortcut: **not possible** (7.4).
- [ ] V6b. The "Ask AI" Control can be assigned to the Watch Action Button and opens the app.
- [ ] V7. "Return to Clock" per-app setting exists on watchOS 27.
- [ ] V8 (Phase 2). H1 / H2 / H3 result delivery timings with the wrist down.

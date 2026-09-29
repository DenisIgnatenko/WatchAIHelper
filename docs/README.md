# AI Copilot - Documentation

Private AI assistant for Apple Watch Ultra 2 and iPhone, backed by a private backend that talks to the OpenAI Responses API.

| Document | Content |
|---|---|
| [phase-0/platform-investigation.md](phase-0/platform-investigation.md) | Verified platform capabilities and limitations (Apple, OpenAI), with sources |
| [phase-3-image-benchmark.md](phase-3-image-benchmark.md) | Model / image-size benchmark on real exam photos |
| [architecture.md](architecture.md) | MVP architecture: structure, data model, API, state machines, sync, testing, phases |

## Current status

- Phase 0 (investigation and design): **done**.
- Phase 1 (Watch spike with mock backend): **done** - device checks V1-V6 passed (V7 open, V8 belongs to Phase 2).
- Phase 2 (backend + OpenAI, text): **done** - deployed on Lightsail (https://<static IP>), Watch asks and gets answers, V8 ok.
- Phase 3 (photos from iPhone): **done**. Image parameters: [phase-3-image-benchmark.md](phase-3-image-benchmark.md).
- Phase 4 (daily use: conversation modes, Action Buttons, camera): **done**.
- Phase 5 (reliability and privacy): **done in code** - cancel / retry Send, conversation rename and delete,
  AI-suggested titles, image retention (30 days), AI cost report, Watch complication, app icons, CI
  (GitHub Actions: backend tests, Swift contract and package tests, opt-in deploy - see
  [deploy/lightsail-setup.md](deploy/lightsail-setup.md), section 7).
- Apple clients: see [../apple/README.md](../apple/README.md).

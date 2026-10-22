# Stage 6 Flutter integration

Continue the existing approved Apple-style Flutter design, developed against merged main `66c4854`. The user requested connecting the latest backend, testing it and leaving a working local preview, then authorized delivery on `ui-phase-6` through a committed, pushed and merged pull request. Preserve all Stage 2–5 flows, BM/EN, accessibility settings and the approved 20-coin rewards. No cloud deployment or backend API changes are included.

## Interface design

Keep the four current destinations. Add a compact updates/progress/community-tools entry to connected screens, opening the existing accessible sheet style. Use the existing surfaces, typography and press feedback. Coordinator tools expose summary, reports, explicit warning review/clear, helper blocking, availability and an operator-run due processor. Residents see their own reports and notifications, permitted progress, and family cheers. Family daily sharing and booking remain independent. Expired warnings stay visible as needing review.

Use all eleven APIs in `docs/BACKEND_COORDINATION.md`. Read results remain server-owned snapshots; refresh on opening/after relevant mutations. Streams use exact recipient/elder/consent or report ownership/request constraints. Cancel affected subscriptions and clear private content on scope/consent change, logout and denial. Mutations use immutable action payloads and one retry key per confirmation; prevent duplicate taps and stale-result updates.

Voice booking accepts text and explicit user-initiated bounded audio capture, shows clarification/read-back, and requires a separate final booking confirmation through `createRequest`. The user chose a connected manual-booking fallback while Gemini is unconfigured. Test injected draft responses separately from real provider-unavailable behavior; never present fixtures as live parsing. No microphone use is automatic and no provider credentials enter Flutter.

## Verification

Fixture/model/controller/widget tests cover exact envelopes and timestamps, all APIs, immutable retry, late responses, logout/consent changes, report privacy, notices, summary suppression, warning expiry, voice failure/manual fallback and BM/larger text at phone/tablet/desktop widths. Run Flutter analysis, tests, browser bridge/startup tests and release build. Exercise real emulator reports/review, warnings, due processing, notifications, progress/cheers, block behavior and parser failure. Preserve the current earned wallet data, add only missing Stage 6 demo configuration using the existing local guard, and leave port 8090 ready with manual steps and screenshots.

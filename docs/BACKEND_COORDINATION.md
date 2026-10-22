# Backend Stage 6: coordinator operations, progress and voice booking

Developer B implements the backend on `backend-coordination-reporting`. Developer A owns every Flutter screen, shared model and repository adapter, including the coordinator screen. This stage builds on merged Stage 5's completion records, reward protection and wallet integration.

Use the existing Auth/Firestore/Functions emulators, project `demo-emascare`, region `asia-southeast1`. No cloud deployment is included. Tanya Dulu stays outside this build. Main now includes the approved **20 coins per verified activity/helping session for both roles**; apply it after seeding with `npm.cmd run demo:configure-rewards`, as described in [the wallet guide](BACKEND_WALLET.md). Stage 6 does not change that policy. Phone help remains excluded from outing progress; standalone sit/carry outing definitions remain pending independently of reward eligibility.

## Interface and examples

Share this guide and [the executable JSON fixtures](fixtures/stage6_coordination.json) with Developer A. Every result is `{ "contractVersion": 1, "data": ... }`. Timestamps in responses are UTC ISO strings, and optional response fields are explicit nulls. Mutation inputs require `contractVersion: 1` and an `idempotencyKey`; use one key per user action, retaining it for retries. Read/parser inputs require `contractVersion: 1` without an idempotency key. Actor identity always comes from Firebase Auth.

| Callable | Caller and input fields | Exact `data` contents |
| --- | --- | --- |
| `setPlaceWarning` | Coordinator: `placeId`, `warning: {level: "warning" / "closed", text, expiresAt}` or null | `{place}` |
| `submitReport` | Signed-in township participant: `kind`, `text`, related IDs below | `{report}` |
| `reviewReport` | Coordinator: `reportId`, `state: "seen" / "done"` | `{report}` |
| `blockHelper` | Actual elder or coordinator: `elderId`, `helperId`, `reason` | `{elderId, helperId, blocked: true}` |
| `sendFamilyCheer` | Currently sharing-consented family: `participationId` | `{cheer}` |
| `markNotificationRead` | Current permitted recipient: `notificationId` | `{notificationId, readAt}` |
| `processDemoDueItems` | Coordinator: no business fields | `{processedAt, remindersCreated, missedAlertsCreated, warningsCleared}` |
| `getProgress` | Scope-specific permission below: `scope`, `entityId`, `periodType`, `periodKey` | `{progress}` |
| `getAvailabilitySummary` | Signed-in profile: no business fields | `{availabilitySummary}` |
| `getCoordinatorSummary` | Coordinator: no business fields | `{summary}` |
| `parseVoiceBooking` | Actual elder or booking-consented family: `elderId`, `locale`, `input` | `{transcript, draft, missingFields, clarification, readBackText, canConfirm}` |

The three named summary read APIs make the previously specified authorized summary reads concrete. They are additive to contract v1; existing settings, availability, session and attendance response envelopes remain unchanged. Use `getProgress` for current results rather than a cached `progress` document. Refresh after completion/review or when the user opens the progress view. `getCoordinatorSummary` is a read snapshot; refresh after an operator action.

Fixtures contain ordered calls from a fixed server time, including real service responses for all the new APIs. They exercise bare seed/reset before applying the approved reward configuration, so they do not show configured coin awards. Their voice result uses an **injected provider**, not a recording or a live Gemini success. Seeded aggregate history is marked separately and never proves an actual completion or coin award.

## Reports, warnings and blocking

`place_problem` needs a same-township `placeId`, `text` (1–1000 characters), optional `requestId`, and null/omitted `helperId`. If linked to a request, the reporter must be its elder, currently booking-consented family, assigned helper or coordinator, and the place must match that request.

`helper_report` needs `requestId`, its actual `helperId`, `text`, and null/omitted `placeId`. The same current request permissions apply. No client can choose the creator, township, review status or metadata. Reports contain `id`, `townshipId`, `createdBy`, `kind`, nullable related IDs/elder/household, `text`, `state`, nullable `reviewedBy`/`reviewedAt`, and creation/update times.

Linked report commands reuse the existing booking access check, including on receipt replay. Moving the elder/family to another household does not grant commands against the former household's request; the coordinator can still follow up. Household progress also requires contributing helpers to remain listed in the household's current member array.

Report states are `new -> seen -> done`, with `new -> done` also allowed. `done` is terminal. Retrying the same mutation key returns its saved result after current authorization. Repeating the current review state with a new key leaves its timestamp unchanged. Reports are visible to their currently authorized creator and the township coordinator; reporting against a helper does not give that helper access to somebody else's complaint.

Warnings require nonempty text up to 300 characters and a strictly future UTC expiry. Their `liveStatus` also records the coordinator and update time. **Expiry means review is needed.** Retain the warning, display that it needs review, and never infer an accessibility/safety clearance. Explicit `warning: null` clears it. The due processor retains the agreed `warningsCleared` field with value **0**; it does not certify expired warnings safe. Coordinator counts separate active warnings from warnings needing review.

Only the actual elder or a same-township coordinator can block a helper for that elder. An elder needs an existing pairing/request relationship. Family cannot block on the elder's behalf. A block has one durable elder/helper identity and prevents subsequent assignment, acceptance and starting. It does not silently cancel an existing booking or discard an in-progress session; a coordinator follows up. There is no client unblock endpoint in this stage.

## Due items and notifications

`processDemoDueItems` is an **operator-run demo processor**, not a background scheduler or push service. Run it with a new action key to process the server's current Malaysia date. It materializes missing daily records for enrolled elders, applies due/grace/pause settings, and preserves the first successful app or coordinator-phone response.

- At due time during grace: one elder reminder.
- At/after grace: one missed-check-in notice per current township coordinator and currently sharing-consented linked family member.
- An initial late run creates missed notices directly; it does not pretend an earlier reminder was delivered.
- Paused or answered check-ins create no new alert. A later answer preserves existing alert history.
- Notice identity includes event/date and recipient; retries and concurrent runs cannot duplicate that notice. Counts report newly created notification records, not attempted sends.

Booking creation, assignment and final completion create `request_updated` notices. Assignment/completion includes the assigned helper. Families get these only under current **booking** consent. Standalone attendance verification/rejection creates `attendance_review` notices under **sharing** consent. Half-confirmation does not send a completed notice. Family cheers notify the elder once.

Notification fields: `id`, `recipientUid`, `elderId`, `kind`, `entityId`, `consentScope` (`none`, `daily_sharing`, `family_booking`), `messageParams`, nullable `readAt`, `createdAt`. Parameters contain only state/date or clap kind. They omit notes, private responses and financial details. Only the recipient can read/mark a notice. Current role, township, family membership and the notice's particular consent scope are rechecked, including receipt replay after withdrawal. The first read time stays unchanged.

Use a targeted stream: `notifications.where(recipientUid == authUid).where(elderId == selectedElderId).where(consentScope == selectedScope).orderBy(createdAt, descending: true)`. Query each applicable scope separately. A broad family inbox query can be denied because it could include withdrawn-consent records. Stop/reset related streams when consent/access changes.

## Progress, cheers and aggregate availability

Example progress read:

```json
{"contractVersion":1,"scope":"elder","entityId":"elder_demo","periodType":"week","periodKey":null}
```

`scope` is `elder`, `helper`, `household` or `township`. `periodType` is `week` or `month`. Null/omitted `periodKey` means the current Malaysia period; an explicit week is its **Monday** `YYYY-MM-DD`, and a month is `YYYY-MM`. Periods include their start and exclude their end.

Progress fields are `id`, `scope`, `entityId`, `periodType`, `periodKey`, `counts`, `targets`, `pendingOutingClassifications`, `latestOuting`, `isDemo`, `includesSeededHistory`, `updatedAt`. Both counts and targets have `outings`, `helpingSessions`, `weekendGiveBack`; absent goals are null and counts are integers. The approved elder weekly outing goal is 2. Other goals come from backend-owned labelled demo configuration.

- Elder: actual elder, sharing-consented linked family or same-township coordinator. Counts canonical verified elder participation with an outing marker once. Physical activities and companion walks count; phone help does not. Standalone sit/carry remains `pending_definition`, visible in `pendingOutingClassifications` rather than guessed as an outing.
- Helper: actual helper or coordinator. `helpingSessions` counts actual mutually confirmed completed requests. Repeated confirmation/cheering cannot add another session. No money fields are returned.
- Household: current members or coordinator. Weekend helping counts completed help by helpers currently in that household. It does not disclose hidden elder check-ins/outings. Reporting period uses final confirmation time; weekend classification uses the request's scheduled Malaysia start day.
- Township: current township profiles. Live outings count **elder** participations only, avoiding an extra outing for the companion. Residents receive `SUMMARY_SUPPRESSED` if fewer than five current elder profiles exist; coordinators may inspect their operational aggregate. No individual outing details are returned for this scope.

Elder `latestOuting` is null or `{participationId, requestId, attendanceId, activityTitle: {bm,en}, completedAt}`. Only this safe projection reaches consented family; underlying reward claims, ledger and participant finance records remain private. Final verification time determines reporting period, not reward eligibility by month.

`sendFamilyCheer` accepts this verified outing's `participationId`. One family member can clap once per underlying participation, even with different action keys or simultaneous taps. No cheer reward exists. Unverified, phone-only and pending-definition outings cannot be cheered. Read cheers with `elderId == selectedElderId` and `createdAt desc`, under current sharing consent.

Availability is a **fixed synthetic table**. At least five distinct synthetic helpers are required per cell; fewer yields `helperCount: null`, `requestCount: null`, `suppressed: true`. Duplicated IDs do not increase the cohort. Fixed disjoint cohorts prevent overlapping-cell differencing. No member IDs, individual schedules or reconstructing grand totals are exposed. These synthetic members are not Auth accounts or assignable helpers. Use `getAvailabilitySummary` or the same-township read-only `availabilitySummaries/{townshipId}` projection. Raw cohort inputs are backend-only.

Seeded prior-weekend household/township counts live in a separate backend-only illustrative-history record. The response sets `includesSeededHistory: true` whenever that period includes them; retain both demo labels in Flutter. They never create attendance, participation, reward claims or wallet entries. The private configuration and public availability projection are seeded together; if changing the synthetic table, update/reseed both.

## Voice parser and live configuration

The endpoint accepts `{type:"text",text}` (up to 1000 characters) or `{type:"audio",mimeType,base64}` (canonical base64, at most **1 MiB decoded**). Accepted MIME labels: `audio/wav`, `audio/x-wav`, `audio/mp3`, `audio/mpeg`, `audio/aac`, `audio/ogg`, `audio/flac`, `audio/webm`. Frontend capture should enforce the agreed **30-second cap** and send a MIME label matching the actual container. Unsupported browser/model/container combinations still require a device smoke test; this implementation does not decode audio to verify duration.

Send the container MIME without codec parameters: for example, a WebM/Opus `MediaRecorder` label `audio/webm;codecs=opus` becomes `audio/webm`. Do not relabel a different container as WebM; retain manual booking if capture is unsupported.

Both text and audio use server-side Gemini when enabled. Provider configuration is disabled by default. Copy [the configuration example](../functions/.env.example) to `functions/.env.local` and configure an enabled, supported model plus your own key locally only when ready for live testing. Do not put a key in Flutter, Git, chat or fixtures. Firebase emulator reads the ignored server environment file; restart Functions after changing it.

The REST adapter follows Google's [audio input](https://ai.google.dev/gemini-api/docs/audio) and [structured output](https://ai.google.dev/gemini-api/docs/structured-output) documentation, using the [generateContent API](https://ai.google.dev/api/generate-content). It requires explicit `GEMINI_ENABLED=true`, `GEMINI_MODEL` and `GEMINI_API_KEY`, sends the key in a header, and has a 20-second network timeout. No model name is silently selected. The adapter has been verified using a local injected transport; **live provider/audio/browser verification remains pending** until a configured provider is available.

Only public township catalog fields, server time/locale and the supplied message/audio go to the provider. User/household IDs are not added. Audio and transcript are not stored. Per-user throttling stores only minute, count and update time, allowing five attempts per server minute, including failed provider calls. The app should explain that a live parsing action sends the submitted content to the configured provider.

Provider output is untrusted. Backend validation checks schema, catalog IDs, supported task and preferences, future minute-aligned times, duration and place consistency. Catalog activity times come from the server. Unresolved fields become nulls with `missingFields` and clarification. A complete draft includes server-selected `elderId`, Malaysian-time readback and `canConfirm: true`. The user must still confirm through existing `createRequest`; parsing never books, assigns, confirms or awards coins. Consent is checked before inference and again before returning a successful draft.

Use manual booking when `VOICE_SERVICE_UNAVAILABLE`, `VOICE_TIMEOUT`, `VOICE_RATE_LIMIT` or `VOICE_INVALID_RESPONSE` occurs. Never display a fixture as a live parser success. Existing role/consent errors remain distinct. `INVALID_AUDIO`, `UNSUPPORTED_AUDIO_TYPE`, `INVALID_LOCALE` and input validation errors need correction before retrying.

## Verification and handoff

Run `npm.cmd test` for the build, focused unit checks and the complete local emulator suite. Stage 6 tests cover actual authenticated callable routes and Firestore reads/writes, report lifecycle, warning expiry, block enforcement, due-date/retry races, separate consent withdrawal, cheering, progress privacy/classification, aggregate suppression, provider transport, rate limits, no parser side effects, reset isolation and exact JSON fixtures. They do not prove browser microphone capture or live Gemini connectivity.

For a Stage 6-only rerun with no emulators already running, use `npm.cmd run test:coordination`. It builds, runs the unit checks, then starts/stops local emulators for the coordination and household-membership regression tests.

Local verification on 22 October 2026: the full suite passed 20 unit and 99 emulator checks. After tightening household-membership permissions, the final focused rerun passed all 20 unit and 16 coordination/membership emulator checks, including exact fixture comparisons. Live Gemini/audio and connected Flutter verification remain separate pending work.

After integrating main's approved reward configuration and wallet UI changes, the TypeScript build and all 24 combined unit checks passed. The shared test command retains both the reward-policy checks and Stage 6 checks; this branch adds no Flutter changes relative to main.

All client writes remain denied. Backend receipts, markers, private aggregate inputs, targets, illustrative history and rate-limit documents remain backend-only. Pilot reads are bounded (500 records per query, voice catalog 50, due batch 50 elders/20 coordinators and 400 writes). Exceeding a bound returns `DEMO_LIMIT_EXCEEDED`, with no partial result or silent truncation. Production pagination, scheduling, push delivery and deployment are later work.

Next: review the diff, commit, push this branch and create a pull request. Share this guide and the JSON file with Developer A, then run the connected UI walkthrough: report/review, warning expiry, block, due processing and consent withdrawal, standalone verification/cheer/progress, and parser failure fallback. Complete a live BM/EN audio test after server credentials/model are configured. Merge after review and track UI/provider verification separately from passing emulator tests.

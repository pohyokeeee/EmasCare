# EmasCare: full three-day implementation and merge plan

> For the prelim submission, use the [current two-day prototype plan and task split](PROTOTYPE_PLAN_2_DAYS.md). It defines three role views, automatic demo matching, and a smaller free-tier scope. This document is retained as a reference for the larger build.

**Team:** two developers. **Time:** three days, eight working hours per developer per day. **Capacity:** 48 person-hours: 40 planned and eight reserved for fixes.

**Outcome:** one deployed Flutter Web application with elder, family, helper, and coordinator views; Firebase authentication and persistence; check-in escalation; activities and access notes; companion booking and completion; real voice-to-booking AI; and a persisted demo rewards wallet.

This document is the source of truth for the three-day implementation scope, task ownership, integration contracts, and merge order. The [original product plan](../Township%20%28SimeDarby%29%20Hackathon%202026.md) remains the product/pilot roadmap. Task IDs below can be copied directly into issues or a project board.

## 1. Scope and delivery goals

### What must be working at the end

| Goal | Required outcome | How we prove it |
| --- | --- | --- |
| G01 — Working stack | Flutter Web + Firebase Auth + Firestore + TypeScript Functions + Hosting | A hosted, authenticated client invokes a deployed function and reads the resulting data. |
| G02 — Four roles | Separate elder, linked family, helper, and coordinator accounts | Each account sees its own permitted interface and data; direct unauthorized calls are rejected. |
| G03 — Saya OK | Daily check-in, elder consent/settings, pause-today, reminder, missed alert | Family sees the permitted daily status; a second overdue fixture alerts the correct recipients once. |
| G04 — Invite out | Six upcoming activities, linked to five places, with manual companion booking | An elder or consented family proxy creates one persisted request. |
| G05 — Access notes | Accessibility details, step-free filter, Maps link, coordinator warning and expiry | A warning changes in another session and disappears on expiry without marking the place safe. |
| G06 — Neighbour companion | Helper availability, approved recurring pairing, coordinator assignment, session actions | A compatible helper accepts, starts, finishes, and confirms; the elder separately confirms completion. |
| G07 — Teman voice | Short BM/EN audio → validated booking draft → spoken read-back → confirmation | AI parsing creates no booking; explicit confirmation creates exactly one. Manual booking remains usable. |
| G08 — Appreciation | 300-coin monthly demo award, ledger, mock voucher redemption | Three historical fixture sessions plus a fourth live completed session qualify; retries cannot duplicate credit/debit. |
| G09 — Trusted support | Text-only Tanya Dulu, place issue, helper report/block, authorized inbox | The trusted recipient sees the item; a block prevents a new assignment to that elder. |
| G10 — Usable release | BM/EN copy, large text/targets, error states, tested permissions, reset/runbook | Release builds, passes focused checks, and completes the demo twice from a clean fixture reset. |

**Release assumptions:** browser delivery; developer A is comfortable with Flutter/Dart; developer B is comfortable with Firebase/TypeScript and basic Flutter forms. Use one Firebase demo project, synthetic people, seeded household links, and seeded approved recurring pairings. No real SDP integration is required to run the demo. Native builds are additional work only after the browser release passes. The estimates are aggressive and assume familiar tools and available cloud access; use the reserved hours and explicit cut rules when those assumptions fail.

### Boundaries carried over from the product plan

| Product area | Three-day treatment |
| --- | --- |
| Elder/family/helper/coordinator workflows | Implement the goals above against the same backend. |
| Household linking, resident verification, helper vetting, recurring-pair trial | Seed accepted synthetic examples. Build permission enforcement, not real verification integrations. |
| Coins and vouchers | Persist simulated monthly awards and mock redemption. No cash, purchases, settlement, transfers, donations, expiry, or phone-buddy reward variants. |
| Gamification | Factual completed-session impact count only. Rings, cheers, collective goals, and milestones are optional later. |
| AI | Real booking parser only. Check-in concern analysis, scam classification, AI prose, and digests are deferred. Tanya Dulu sends the question to a trusted human. |
| Notifications | Persistent in-app alerts required. Background FCM is optional and must be demonstrated separately. |
| Places and reports | Five illustrative seeded places and text reports. Field verification, photo uploads/triage, and routing are deferred. |
| Remaining roadmap | SDP embedding/SSO, merchant integration, WhatsApp/SMS, heatmap, ratings, mascot, production read-access auditing, and app stores are outside this sprint. |

Completing every original MVP feature and production integration would need a longer schedule. The acceptance tests in this document define completion of this three-day build.

## 2. Fixed architecture

```text
One Flutter app
  Elder | Family | Helper | Coordinator
        |
        +-- Firebase Auth -> authenticated identity
        +-- Firestore streams -> authorized screen data
        +-- callable Functions -> validated state changes
                                  |
                                  +-- Firestore transactions + audit events
                                  +-- Gemini API -> booking draft only
                                  +-- scheduled maintenance -> due alerts/status expiry

Flutter static release -> Firebase Hosting
```

- Use standard Flutter widgets and a small typed API/repository layer; do not introduce a second frontend.
- Use TypeScript Cloud Functions for domain rules. Keep scheduling and AI within this backend.
- Clients may update their own notification read marker under narrowly scoped rules. Other domain mutations go through the commands in section 4.
- Bundle place images/placeholders. Do not add a Cloud Storage upload pipeline during core work.
- Use Flutter's existing localization tooling for BM/EN and a tested device/browser TTS adapter. Check microphone and voice availability on the actual presentation device on Day 1.
- B selects and records supported Firebase locations/runtime and a configurable Gemini Flash model after a real project smoke check. Never put the Gemini key in Flutter or tracked configuration.
- Firebase billing/project access is a kickoff dependency. Cloud Functions deployment requires Blaze, per the [Firebase setup guide](https://firebase.google.com/docs/functions/get-started). Web release follows the [Flutter deployment guide](https://docs.flutter.dev/deployment/web).

## 3. Ownership that prevents overlapping edits

### People and review responsibilities

| Responsibility | Developer A | Developer B |
| --- | --- | --- |
| Main implementation | Resident Flutter application | Backend, Firebase infrastructure, coordinator Flutter feature |
| Shared Dart contracts and API adapter | Sole writer | Reviews behavior against backend contracts |
| Wire schema and fixture definitions | Reviews client needs | Sole writer |
| Routing, translations, widgets, dependencies | Sole writer | Reuses provided components; requests additions |
| Backend business logic, rules, indexes | Reviews user-visible behavior | Sole writer |
| Release integration | Supplies Flutter release and resident smoke checks | Sole merge/deployment coordinator |

### File ownership registry

The owner is the only person who commits changes to that path. A requested change is implemented by the owner. This applies to generated files as well as handwritten code.

| Path | Owner | Contract with the other developer |
| --- | --- | --- |
| `app/lib/main.dart`, `app/lib/app/**` | A | Register all four routes once at foundation; do not make B change the router. |
| `app/lib/contracts/**` | A | Dart models/enums match the B-owned v1 wire schema. |
| `app/lib/api/**` | A | Typed reads and callable adapter, including methods needed by coordinator. |
| `app/lib/shared/**` | A | Shared cards, inputs, status chips, loading/error widgets. |
| `app/lib/features/elder/**` | A | Elder screens and actions only. |
| `app/lib/features/family/**` | A | Family status and proxy booking only. |
| `app/lib/features/helper/**` | A | Availability, sessions, wallet only. |
| `app/lib/features/coordinator/**` | B | Coordinator screen exports one agreed widget; imports shared API/contracts. |
| `app/lib/l10n/**`, `app/assets/**` | A | B supplies coordinator translation keys/copy before A's localization pass. |
| `app/pubspec.yaml`, `app/pubspec.lock`, `app/analysis_options.yaml` | A | B requests dependencies; B does not run an upgrade or commit a changed lockfile. |
| `app/web/**`, optional native platform directories | A | No platform regeneration by B after foundation. |
| `app/lib/firebase_options.dart` | B | Single generated Firebase configuration; A imports it. |
| `app/test/**` except `app/test/coordinator/**` | A | Resident/API wire-decoding checks. |
| `app/test/coordinator/**` | B | Coordinator checks only when useful. |
| `contracts/v1/**` | B | JSON schemas and shared request/response/fixture examples; frozen at M0. |
| `functions/**`, `scripts/**` | B | Includes TS types, backend/rules tests, seed/reset/evaluation scripts. |
| `firebase.json`, `.firebaserc`, `firestore.rules`, `firestore.indexes.json` | B | B alone initializes/reconfigures Firebase and changes deployment paths. |
| Root `.gitignore`, `.github/**`, `README.md`, `docs/**` | B | A sends documentation and ignore-file additions to B. |
| `app/.gitignore` and other app-scaffold files | A | Keep app-generated edits inside A's paths. |

**Exception:** B creates the initial coordinator placeholder during foundation, then continues to own it. A registers the placeholder import. No other cross-owner exception is needed.

**Generated-file rules:** run FlutterFire configuration once on the integrated foundation under B's control; review its complete diff with A before M0. After M0, B owns its root/Firebase outputs and A owns app dependency/platform outputs. Never commit `.dart_tool/`, `build/`, `node_modules/`, emulator data, credentials, or generated files unrelated to the feature. If a CLI changes another owner's file, send the diff to that owner rather than committing it.

### Three stable integration seams

1. **Screen seam:** B exports `CoordinatorScreen({required EmasApi api, required UserSession session})`. A imports it from `features/coordinator/coordinator_screen.dart`. B never edits `main.dart` or route registration.
2. **Client seam:** A exports `EmasApi` from `api/emas_api.dart` and `UserSession`/shared models from `contracts/`. B uses this API rather than writing a second Firebase adapter.
3. **Backend seam:** B exports the callable names and wire fields in section 4. A's adapter translates wire JSON and Firestore timestamps into Dart models. UI screens never construct arbitrary document updates.

At M0, every method exists with its final signature, and the coordinator placeholder compiles. Temporary fixture implementations may support isolated UI work; the integration gates require the real deployed adapter. Production/demo release must not silently fall back to fake success.

## 4. Contract v1: agree before feature implementation

### Common conventions

| Item | Exact convention |
| --- | --- |
| API version | Include `contractVersion: 1` in command input and result. B records JSON schemas/examples in `contracts/v1/`. |
| IDs | Firestore document IDs as strings. APIs never accept an actor UID as proof of identity; derive actor from Firebase Auth. |
| Roles | `elder`, `family`, `helper`, `coordinator`. Role/household/approval fields are server-owned. |
| Wire times | UTC ISO-8601 strings, including `Z`; Firestore stores Timestamp fields. The Dart adapter converts both representations. |
| Local date/month | `YYYY-MM-DD` / `YYYY-MM` in `Asia/Kuala_Lumpur`, computed by backend logic. |
| Daily settings | `dueLocalTime` in `HH:mm`; `graceMinutes` integer; `pausedOn` local date or null. |
| Availability | `weekday` 1–7, Monday=1; `startMinute`/`endMinute` since local midnight; interval start included, end excluded. |
| Task types | `walk_with_me`, `sit_with_me`, `phone_help`, `carry_light_item`. |
| Preferences | `preferredLanguage`: `bm` or `en`; `preferredHelperGender`: `any`, `female`, `male`. Seeded approved helper profiles include matching fields. |
| Optional data | Explicit null where specified by schema. Do not alternate between empty strings, missing fields, and null. |
| Retry protection | Generate one `idempotencyKey` per user intent and retain it across retries/double taps. Server binds key to actor, command, and payload. A new confirmed intent gets a new key. |
| Results | `{contractVersion: 1, data: {...}}`; typed callable errors for failures, never a success-shaped error object. |
| Error codes | `unauthenticated`, `permission-denied`, `invalid-argument`, `not-found`, `failed-precondition`, `already-exists`, `unavailable`. A maps these to localized messages. |
| Translations | Enum values stay in English; visible labels use BM/EN keys. Do not persist translated state names. |

### Collections, minimum fields, and read boundaries

| Document | Minimum fields | Authorized readers |
| --- | --- | --- |
| `users/{uid}` | `role`, `householdId?`, `townshipId`, `displayName`, `locale` | Own account; coordinator reads only as required. Helper details needed by residents go in an assigned-session projection. |
| `elderSettings/{elderId}` | `familySharingEnabled`, `familyBookingEnabled`, `dueLocalTime`, `graceMinutes`, `pausedOn` | Elder and coordinator; family cannot change consent. Daily-status sharing and proxy-booking consent are separate switches. |
| `households/{id}` | `elderIds`, `familyUids`, `townshipId` | Household members and coordinator. Seed/server mutations only. |
| `helperProfiles/{uid}` | `approved`, `tier`, `languages`, `gender`, `allowedTasks`, `availability[]` | Own helper and coordinator. Residents do not browse helper schedules. |
| `pairings/{id}` | `elderId`, `helperId`, `active`, `allowedTasks`, `bothAccepted` | The pair and coordinator. Seed/server mutations only. |
| `checkins/{elderId_localDate}` | `elderId`, `localDate`, `state`, `dueAt`, `graceEndsAt`, `submittedAt?`, `recordedBy?`, `source` | Elder and coordinator. Keep family-visible summaries separate. |
| `dailyStatuses/{elderId_localDate}` | `elderId`, `householdId`, `localDate`, `state`, `updatedAt` | Elder, consented linked family, coordinator. No private reply text or location. |
| `places/{id}` | `name`, `townshipId`, `stepFree`, `accessibleToilet`, `seating`, `walkMinutes`, `notesBm`, `notesEn`, `imageAsset`, `mapsUrl`, `liveStatus?` | Signed-in demo residents/coordinator in the same township. |
| `activities/{id}` | `titleBm`, `titleEn`, `placeId`, `townshipId`, `startsAt`, `endsAt`, `language` | Signed-in users in that township. |
| `requests/{id}` | `elderId`, `householdId`, `createdBy`, `placeId`, `activityId?`, `startsAt`, `endsAt`, `taskType`, preferences, `pairingId?`, `helperId?`, `state`, session/confirmation timestamps | Elder, consented linked family, assigned helper, coordinator. Only non-private meeting/session data is stored here. |
| `helperReservations/{helperId_localDate}` | Helper/date and active request intervals | Backend/coordinator only. Assignment/cancellation transitions update this document transactionally to prevent concurrent overlapping assignments. |
| `notifications/{id}` | `recipientUid`, `kind`, `entityId`, `elderId?`, `requiredConsent?`, `createdAt`, `readAt?`, minimal message parameters | Recipient only, plus the current elder consent required by the notification kind (`daily_sharing` or `proxy_booking`). Read markers are the only narrowly allowed direct client mutation. |
| `reports/{id}` | `createdBy`, `elderId?`, `kind`, `text`, related IDs, `recipientUids`, `state`, `createdAt` | Author, listed trusted recipients, coordinator. Family readership requires current consent. |
| `helperBlocks/{elderId_helperId}` | `elderId`, `helperId`, `createdBy`, `createdAt` | Elder and coordinator; assignment service checks it. No public block list. |
| `wallets/{uid}` + `wallets/{uid}/entries/{entryId}` | Server-owned `balance`; immutable `type`, `amount`, `month?`, related IDs, `createdAt` | Own helper and coordinator. |
| `auditEvents/{id}` | `actorUid`, `action`, `entityId`, `createdAt`, small mutation metadata | Coordinator. Backend-only writes; this is a mutation log, not complete read auditing. |
| `commandReceipts/{id}` | Actor/command/key, payload hash, stored result, timestamp | Backend only; records transactional duplicate protection. |

Consent checks apply to Firestore reads as well as commands. `familySharingEnabled` gates daily-status and related check-in-alert reads, including old records; `familyBookingEnabled` gates family request reads and proxy booking/cancellation. Support questions go to a linked family recipient only when sharing is enabled; otherwise route to the coordinator. Existing support readership and related notification reads also check current sharing consent. Helpers never receive private elder settings, household status, or a home address. Firestore cannot hide selected fields within an otherwise readable document, hence the separate `dailyStatuses` collection. Backend libraries bypass client rules; B validates permissions within every function as explained in [Firebase's rules guide](https://firebase.google.com/docs/firestore/security/rules-conditions).

### Callable commands

All commands include `contractVersion`. All domain writes also include `idempotencyKey`; the read-only parser is exempt.

| Callable | Required business input | Result data | Permission |
| --- | --- | --- | --- |
| `saveCheckInSettings` | `familySharingEnabled`, `familyBookingEnabled`, `dueLocalTime`, `graceMinutes`, `pausedOn` | Updated settings | Elder changes own settings only. |
| `submitCheckIn` | `elderId`, `source: app` | `{checkinId, state}` | Actual elder; do not accept client-supplied dates or submitted timestamps. |
| `saveAvailability` | `slots[]` using the weekday/minute convention | Normalized slots | Helper edits own availability only. |
| `createRequest` | `elderId`, `activityId?`, `placeId`, `startsAt`, `endsAt`, `taskType`, preferences | `{requestId, state: requested}` | Elder or linked family with current proxy consent. |
| `transitionRequest` | `requestId`, `action`, assignment-only `helperId?` | `{requestId, state}` | Server action/actor matrix below. |
| `parseVoiceIntent` | Authorized `elderId`; either `audioBase64` + `mimeType`, or `text`; `locale` | `{draft, readBackText, missingFields[]}` | Actual elder or linked family with booking consent. Server attaches the authorized elder ID to the draft; AI never chooses it. Confirmation rechecks authorization. |
| `setPlaceStatus` | `placeId`, `level`, `text`, `expiresAt`; `level` is `warning`, `closed`, or `clear` | Updated status or null | Coordinator only; expiry required for a non-clear status. |
| `createSupportReport` | `kind`, `text`, optional related `elderId`, `placeId`, `requestId`, `helperId` | `{reportId}` | Authorized participant; server determines trusted recipients. Only the actual elder or coordinator may use `block`, which also writes `helperBlocks`. |
| `awardMonthlyThanks` | `helperId`, `month` | `{entryId, credited, balance}` | Coordinator; month is Malaysia-local; eligibility checked server-side. |
| `redeemDemoVoucher` | `voucherId` | `{entryId, voucherCode, balance}` | Own helper wallet; backend fixes voucher cost. |
| `reviewSupportReport` | `reportId`, `state: seen` or `done` | Updated report | Coordinator or authorized trusted recipient. |
| `runDemoMaintenance` | No arbitrary timestamp or document path | Processing summary | Coordinator + demo environment only; processes fixed demo fixtures using current server time. |

`readAt` updates cannot change notification recipients, content, or kind. `createRequest` checks activity/place consistency, start/end ordering and permitted tasks. Display-only text and AI text never authorize a transition.

### Booking action matrix

| Action | Actor | Allowed starting state | Result |
| --- | --- | --- | --- |
| `assign` | Coordinator | `requested` | `assigned`; server selects an active accepted pairing with the supplied helper after compatibility checks. |
| `accept` | Assigned helper | `assigned` | `accepted` |
| `start` | Assigned helper | `accepted` | `in_progress`; set server start timestamp. |
| `finish` | Assigned helper | `in_progress` | `awaiting_confirmation`; set server finish timestamp. |
| `confirm` | Actual elder or assigned helper | `awaiting_confirmation` | Record that actor's confirmation; set `completed` only after both exist. |
| `cancel` | Elder, consented family proxy, or coordinator | `requested`, `assigned`, `accepted` | `cancelled`; never counts for rewards. |

Assignment checks approved status, sufficient task tier, active accepted pairing, language/gender preferences, full availability coverage, blocks, and overlap with the helper's other active sessions. Use a transaction that also touches a helper/date reservation document so competing assignments cannot both bypass the overlap check. Only assigned requests are visible in the helper queue; there is no open task market.

### Streams required by both UI owners

A exposes typed methods for session/profile, elder settings, daily status, activities/places, own or household requests, own notifications, helper profile/wallet/ledger, and coordinator queues/pairings/reports. B writes a query/index checklist for these streams in `docs/CONTRACTS.md` at M0. Queries include the same ownership/recipient constraints as rules; UI filtering of a broad unauthorized query is not acceptable. Use recipient-array queries for reports and helper ID queries for assigned requests. Do not try to store family/helper unreadable private data in the public activity documents.

## 5. Three-day timeline and merge checkpoints

Hours are working hours within that day. The final row of each day is contingency. Joint checkpoints count toward both people's budgets.

### Day 1 — establish the complete stack and first connected flow

| Hours | Developer A | Developer B | Required output |
| --- | --- | --- | --- |
| 0–2 | A01: Flutter scaffold, shared API/models, role routes, widgets, localization shell | B01: cloud setup, v1 contract/fixtures, Firebase config, coordinator placeholder, deployment setup | **M0:** integrated foundation; all shared signatures frozen; hosted skeleton/callable smoke check |
| 2–4 | A02: login, elder check-in/settings, family daily status | B02: seeded identities/roles, household/consent rules, repeatable fixtures | Roles and permitted data work against the demo project |
| 4–5.5 | A03: activities/access details/filter and manual booking | B03: check-in/settings, availability and request commands; continue until hour 6.5 | Activities point at real places; requests use v1 fields |
| 5.5–6.5 | A04: helper queue/availability, microphone/TTS smoke check | B03 continued: minimal coordinator request queue and real adapters smoke check | Resident screens connect to real backend |
| 6.5–7 | I01: merge and cross-account check with B | I01: ordered merge/deploy and cross-account check with A | **M1:** hosted login → check-in → family; activity → request → coordinator |
| 7–8 | Reserved for blockers | Reserved for blockers | Protect Day 1 gate |

**Day 1 goal:** G01/G02 delivered; the connected foundations of G03/G04/G05/G06 run against Firebase. Real audio capture/TTS and Gemini access have been independently smoke checked, even though the full voice workflow is Day 2.

### Day 2 — complete every core demonstration feature

| Hours | Developer A | Developer B | Required output |
| --- | --- | --- | --- |
| 0–2 | A05: session accept/start/finish, separate confirmations, family completion | B04: due-time scheduling/alerts; place status/expiry; text support/block commands | Check-in and access/support lifecycle exists |
| 2–3.5 | A06: voice UI/adapter/read-back; continue until hour 4 | B05: coordinator assignment/status/support/award controls; state and reservation logic | **M2 at 3.5:** connected manual session and coordinator actions |
| 3.5–4 | A06 continued | B06: Gemini parser; continue until hour 5 | Compatible audio/text draft contract |
| 4–5 | A07: support/report, wallet and redemption UI; continue until hour 6 | B06 continued: parser validation, ambiguity/errors | Voice draft and confirmation use manual booking command |
| 5–6 | A07 continued | B07: monthly award and redemption transactions | Rewards work from actual completed sessions |
| 6–7 | I02: integrate all resident journeys | I02: merge/deploy, maintenance and reward checks | **M3:** full demo passes; freeze features |
| 7–8 | Reserved for blockers | Reserved for blockers | Repair integration; no optional expansion |

**Day 2 goal:** G03–G09 delivered. Check-in, voice-confirmed booking, assignment, access warning, two-sided completion, family update, support inbox, and monthly thanks/redemption work together.

### Day 3 — stabilize and deliver

| Hours | Developer A | Developer B | Required output |
| --- | --- | --- | --- |
| 0–2 | A08: BM/EN copy, semantics/text scaling, loading/empty/error feedback | B08: permissions, transactions, scheduler, reservation and expiry regression checks | High-risk failures fixed; required checks green |
| 2–3 | A09: actual-device voice/error/offline checks | B09: 20-example BM/EN/mixed voice evaluation and prompt correction if justified | AI results and known limitations recorded |
| 3–4 | I03: Flutter release + final two-session smoke test | I03: sequential backend/rules/index/Hosting release + smoke test | **M4:** release candidate deployed |
| 4–6 | I04: two complete rehearsals, screenshots, backup recording, resident handover | I04: fixture reset verification, final runbook, deployment/account handover | **M5:** G10 accepted and release handed over |
| 6–8 | Reserved for release blockers | Reserved for release blockers | No new features |

**Budget:** A = 7 + 7 + 6 = 20 planned hours; B = 20 planned hours. Four contingency hours each bring the total to 48 person-hours. Research/site visits, learning a new framework, and native packaging are not included.

## 6. Goal-by-goal work checklist

Every task must include its task ID in the PR, respect its owned paths, and satisfy its acceptance checks before its checkpoint is marked passed.

### Day 1 tasks

**A01 — Foundation client, 2 h; supports G01/G02.** Depends on the initial v1 contract agreement with B01; both happen in the first block.

- [ ] Create Flutter project under `app/`; add Firebase/Auth/Firestore/Functions and chosen voice/TTS dependencies once.
- [ ] Build Dart enums/models and `EmasApi` signatures for all section 4 commands/streams, including coordinator needs; add representative wire-decoding checks.
- [ ] Add login shell and four role routes; register B's coordinator placeholder without requiring later router edits by B.
- [ ] Add shared action button, status chip, form/error/loading components and BM/EN localization shell. Use existing Flutter state primitives or the approach A already knows.
- [ ] Configure the client region/project from B's supplied values; distinguish emulator development from deployed demo explicitly.

**Done:** client compiles, placeholder coordinator route works, the API surface is importable by B, and the hosted smoke command succeeds. No secrets are in app assets or source.

**B01 — Foundation backend/contracts, 2 h; supports G01/G02.** Runs alongside A01.

- [ ] Verify CLI/toolchains, project permissions, billing, Auth provider, supported runtime/locations, and Gemini key/quota.
- [ ] Commit `contracts/v1/` examples/schema and `docs/CONTRACTS.md` with enums, payloads, stream queries/indexes, and the signed-off ownership registry.
- [ ] Initialize `functions/`, test/build scripts, Firebase root config, deny-by-default rules and indexes; create the coordinator placeholder in B's folder.
- [ ] With A's scaffold integrated, run the one controlled FlutterFire setup and review all generated edits; establish ignored secrets/local credentials files.
- [ ] Deploy a tiny authenticated smoke callable and static skeleton; successfully call Gemini once from the server-side environment.

**Done:** M0 foundation exists on `main`; both developers can build/start from it. Deployment is proven before business feature work.

**A02 — Identity/check-in/family screens, 2 h; supports G02/G03.** Depends on M0; develops against fixtures until B02/B03 are ready.

- [ ] Implement actual Auth login/logout and role routing from server-owned profile data.
- [ ] Build the elder four-button home: Saya OK, Jom Keluar, Minta Teman, Tanya Dulu.
- [ ] Build check-in/settings with separate daily-sharing and proxy-booking consent, due/grace time, and pause-today; disable duplicate submissions and preserve retry keys.
- [ ] Build family daily status with consent-aware access handling; subscribe to recipient alerts.

**Done:** actual elder check-in changes only the linked consented family's permitted status; family cannot change elder consent. Loading/permission errors are visible.

**B02 — Identity, rules and fixtures, 2 h; supports G02/G03/G04.** Depends on M0.

- [ ] Seed elder/family/helper/coordinator plus unrelated-family, blocked/unapproved-helper, and overdue-elder test identities.
- [ ] Seed one township, linked households, accepted pairings, five places, six upcoming activities, helper availability, and three eligible historical confirmed sessions.
- [ ] Implement role/relationship/consent-aware reads and backend authorization helpers; users cannot self-edit role, vetting, household, ledger, or pairing approval.
- [ ] Create focused negative tests for unrelated reads and unauthorized writes. Seed fixtures with the same v1 field names used by A.

**Done:** fixtures are reproducible; authorized access works; unrelated account/role-escalation cases fail. Reset is restricted to the isolated demo project and known fixture IDs.

**A03 — Activity/access/manual booking UI, 1.5 h; supports G04/G05.** Depends on A01 and v1 fixtures.

- [ ] List/sort upcoming activities, join each place's access details, and add step-free filtering.
- [ ] Show toilet, seating, walk time, notes, external Maps link, and warning/closed state.
- [ ] Implement manual activity booking and a simple place/task/time form shared by elder and consented family proxy.
- [ ] Show success only after a server result; retain the command retry key until success or explicit new intent.

**Done:** booking persists with consistent activity/place/time fields and appears in the coordinator queue.

**A04 — Helper foundation/device check, 1 h; supports G06/G07.** Depends on A01/A03.

- [ ] Build own assigned-session list and own availability editor using the agreed weekday/minute format.
- [ ] Show approved helper/tier information as seeded data, without exposing other households' status.
- [ ] Capture/replay a short audio clip and speak a BM/EN sample on the actual demo browser/device; report MIME/voice support to B.

**Done:** helper sees only assigned sessions; availability round-trips; microphone/TTS incompatibilities are found on Day 1.

**B03 — First domain commands, 2.5 h; supports G03/G04/G06.** Depends on B01/B02.

- [ ] Implement `saveCheckInSettings`, `submitCheckIn`, `saveAvailability`, and `createRequest` with Auth, relationship, schema, and idempotency checks.
- [ ] Atomically write the daily family-safe projection where permitted; handle consent withdrawal and pause-today coherently.
- [ ] Reject invalid/past activity data and mismatched place/time references; store request actor from Auth.
- [ ] Add the minimal coordinator queue using the shared Dart API; add needed query indexes and a domain mutation audit event.

**Done:** I01 runs against deployed functions with actual accounts; repeated submit/retry produces one result. Remaining scheduled escalation is B04.

**I01 — Day 1 integration, 0.5 h each.** Depends on A01–A04/B01–B03.

- [ ] Merge B's backend/config before A's business screens, then rebuild/deploy the integrated result.
- [ ] Run elder check-in → family status, and activity → persisted request → coordinator queue.
- [ ] Try the unrelated family account; verify refusal rather than an empty-looking success. Record M1 evidence and blockers.

### Day 2 tasks

**A05 — Resident session lifecycle, 2 h; supports G06.** Depends on M1 and the frozen transition matrix.

- [ ] Add helper accept/start/finish/confirm actions and the elder's separate confirmation action.
- [ ] Build UI from server state; pending confirmations identify which action remains without permitting one account to confirm for another.
- [ ] Show matched helper name/tier/meeting information only to authorized participants; update family completion and factual impact count.
- [ ] Disable invalid actions locally while still handling backend rejection. No optimistic completion or client-issued rewards.

**Done:** separate authenticated helper/elder actions produce one completed session; unauthorized/out-of-order actions fail.

**B04 — Scheduling, places, support, 2 h; supports G03/G05/G09.** Depends on B03.

- [ ] Implement scheduled maintenance that materializes due daily records even when the elder never opened the app; reminder and grace expiry create deterministic recipient alert IDs.
- [ ] Use transactions to avoid a stale missed alert racing with check-in; skip paused local dates and preserve late-check-in alert history.
- [ ] Implement `setPlaceStatus`, expiry cleanup, `createSupportReport`, `reviewSupportReport`, and block persistence; route support recipients on the server.
- [ ] Add demo-only authenticated maintenance for fixed fixtures and current server time. Expired warnings are hidden by clients independently of cleanup.

**Done:** repeated maintenance creates no duplicate alerts, pause suppresses alerts, warnings expire, reports arrive at trusted recipients, and blocks are enforceable by B05.

**B05 — Coordinator and assignment, 1.5 h; supports G05/G06/G08/G09.** Depends on M1/B04; consumes A's frozen shared API.

- [ ] Implement assignment/state transitions and helper/date reservation transactions; validate tier, pairing, preferences, blocks, availability, and conflicts.
- [ ] Complete coordinator tabs: check-in exceptions/support; requests and compatible helper assignment; places/status editor. Add report seen/done actions.
- [ ] Add monthly-award control with explicit eligible/pending feedback; it calls B07 once ready, using the already frozen API.
- [ ] Keep widgets inside `features/coordinator/`; use Material/shared controls without modifying router, dependencies, or translation files.

**Done:** M2 manual session journey works across accounts; incompatible/overlapping assignments fail; support/status editing is usable.

**A06 — Voice workflow, 2 h; supports G07.** Depends on A04 and parser response fixture; live hookup depends on B06.

- [ ] Record a bounded clip with actual MIME type; provide typed text fallback and visible processing/error state.
- [ ] Show a validated editable draft and read it back; highlight missing fields rather than inventing defaults.
- [ ] Confirm by calling the same `createRequest` adapter as the manual form; cancel discards the draft with no write.
- [ ] On permission/API errors keep the manual workflow available; do not auto-submit after transcription or TTS.

**Done:** one live audio request becomes one explicitly confirmed booking. Parsing, editing, cancellation, and retry behaviors are observable.

**B06 — AI booking parser, 1.5 h; supports G07.** Depends on B01 audio/API smoke check and v1 parser schema.

- [ ] Validate authenticated input, supported MIME, duration/size, timeout and per-user request bounds; keep API credentials server-side.
- [ ] Send only necessary public activity/place context to a configurable Flash model; request the small structured draft schema.
- [ ] Resolve relative times using server reference time/Malaysian timezone; validate returned IDs/times/tasks/preferences against real domain data.
- [ ] Return missing-field/ambiguity information and factual read-back text. Never write a request in the parser; never choose a helper.

**Done:** real audio/text parse returns v1 data; bad IDs, missing dates, unavailable service, and unsupported media have predictable responses. Schema-valid JSON is still value-validated, as required by the [Gemini structured-output guide](https://ai.google.dev/gemini-api/docs/structured-output).

**A07 — Support and demo wallet UI, 2 h; supports G08/G09.** Depends on A01/A05; uses B04/B07 commands.

- [ ] Build shared text-support form variants for Tanya Dulu, place problem, helper report/block; author can see submission status.
- [ ] Build recipient inbox entries/read markers and authorized support review where needed.
- [ ] Show wallet balance, immutable entries, monthly thanks, factual completion count, and fixed mock voucher redemption.
- [ ] Clearly label simulated coins/vouchers; preserve idempotency keys and surface insufficient balance/retry errors.

**Done:** support goes to a trusted recipient; blocked helper cannot be newly assigned; award/redemption updates from server streams survive refresh.

**B07 — Reward transactions, 1 h; supports G08.** Depends on completed-session state from B05 and seeded history from B02.

- [ ] Implement coordinator-only monthly eligibility: four distinct mutually confirmed in-person sessions in the same active regular pairing/month; never count cancelled or partially confirmed requests.
- [ ] Use one deterministic credit entry per helper/month across all pairings; transaction writes credit, ledger, and balance once.
- [ ] Implement server-priced fixed mock voucher, atomic funds check/debit/receipt, and idempotent redemption result.

**Done:** fourth completed session qualifies; repeated/concurrent award or redemption cannot duplicate balance changes; insufficient funds fails.

**I02 — Full integration and freeze, 1 h each.** Depends on A05–A07/B04–B07.

- [ ] Merge in section 7 order; deploy current rules/indexes/backend, then the Flutter release.
- [ ] Run all G03–G09 flows with actual separate accounts; use one live fourth session for the reward demo.
- [ ] Verify alert/expiry behavior with fixed demo fixtures; record M3 and stop feature additions.

### Day 3 tasks

**A08 — Usability/translation hardening, 2 h; supports G10.** Depends on M3.

- [ ] Finish BM/EN keys across all views using B's supplied coordinator copy; check language switching.
- [ ] Check 200% text scaling, readable contrast, large labelled tap targets, semantics, and keyboard/focus behavior on the browser release.
- [ ] Complete loading/empty/permission/failure states; require server confirmation before showing success; show stale/offline status rather than claiming a fresh check-in.

**Done:** four elder-home actions remain usable, key text is not clipped, and every demonstrated action has a readable error/retry path.

**B08 — Backend/rules regression, 2 h; supports G10.** Depends on M3.

- [ ] Test unrelated-family reads, withdrawn consent, self-edited role/approval, unauthorized coordinator command, and helper data isolation.
- [ ] Test pause/local-date boundaries, check-in/scheduler race, duplicate maintenance, status expiry, and late check-in.
- [ ] Test incompatible/overlapping assignment, invalid transition, distinct participant confirmation, duplicate award/debit, and insufficient balance.
- [ ] Confirm client and server validation, required indexes, and mutation audit records. Fix failures within B's paths; send A any client mismatch.

**Done:** targeted checks pass and failures cannot be bypassed by calling functions directly. Do not spend the sprint chasing a coverage percentage.

**A09 — Device/failure validation, 1 h; supports G07/G10.** Depends on A08.

- [ ] Test microphone denied, no suitable TTS voice, parser timeout, ambiguous request, interrupted network, double tap, and refresh mid-flow.
- [ ] Check the presentation device and an independent browser session; verify no fake fixture fallback is enabled in the release.

**Done:** manual fallback remains usable; incomplete actions are represented honestly; no duplicated booking from retries.

**B09 — AI evidence, 1 h; supports G07/G10.** Depends on B06.

- [ ] Run 20 labelled examples: BM, EN, mixed speech, missing details, irrelevant/out-of-scope requests, and unsupported/past activity references.
- [ ] Record exact-field correctness, appropriate clarification, latency/failures, and whether confirmation was required; keep fixtures and results under B's owned scripts/docs.
- [ ] Make a prompt/schema adjustment only for a demonstrated failure, then rerun affected examples.

**Done:** measured results exist. Do not describe this small smoke test as the original plan's larger real-elder usability benchmark.

**I03 — Release candidate, 1 h each.** Depends on A08/A09/B08/B09.

- [ ] Run the required build/check commands from section 9 on the integrated commit.
- [ ] Deploy with B as the only deployer; verify the hosted origin uses the intended project/region/backend and current bundle.
- [ ] Smoke check login, real mutation/stream, live parser, and coordinator view. Record M4 URL and commit.

**I04 — Rehearsal/handover, 2 h each.** Depends on M4.

- [ ] Reset known fixture data; complete the five-minute demo twice with separate accounts and no direct database edits.
- [ ] Verify one deliberately overdue elder and one expiring warning; record backup video and screenshots.
- [ ] Finish `docs/DEMO_RUNBOOK.md`, measured results, final delivered/deferred checklist, securely shared accounts, URL, and release commit. Mark M5 only after the final acceptance table passes.

## 7. Branches, merge order, and contract changes

### Foundation and feature branches

Both developers use independent clones/worktrees, not one shared working directory. B coordinates `main`; nobody pushes an unfinished feature directly to it.

1. **Foundation block:** A creates the Flutter/shared client foundation on `bootstrap/a-client`; B creates contracts/Firebase/backend/placeholder on `bootstrap/b-platform`. Their committed paths follow section 3.
2. B merges A's scaffold, then B's platform/contract work. B runs the controlled configuration step against that integrated scaffold; A reviews any app outputs. This establishes **M0**.
3. Both fetch M0 before creating `day1/a-resident` and `day1/b-domain`. On Day 2 use `day2/a-sessions` / `day2/b-operations` for M2 and separate `day2/a-voice-support-wallet` / `day2/b-ai-rewards` branches for M3. Day 3 uses new short branches from M3.
4. Each author fetches `origin/main` and merges it into their feature branch before final checks/PR review. B merges approved PRs one at a time and runs the checkpoint checks on the resulting `main` commit.
5. After a checkpoint merges, start the next branch from updated `main`; do not continue on a branch whose earlier PR was already merged.

If A05 is finished before B05, A opens the sessions PR and starts the independent voice work on its own branch from current `main`, using the M0 API surface. When M2 lands, A synchronizes the voice branch with that accepted commit before completing it. Unfinished voice work must never be included in the M2 sessions PR. B likewise finishes/merges operations separately from AI/rewards. M2 review time is included in these task blocks; the one-hour I02 block is the final combined integration at M3.

Example synchronization on a developer's own feature branch:

```text
git fetch origin
git switch <your-current-feature-branch>
git merge origin/main
# Run the required checks; review only your owned paths.
git push origin <your-current-feature-branch>
```

No force pushes, blanket conflict acceptance, or merge commits that replace another person's feature. If a textual conflict appears, stop the merge, identify the owner, and have that owner provide the intended combined change. Do not resolve it by silently choosing one side.

### Ordered integration gates

| Gate | When | Merge order | Evidence required |
| --- | --- | --- | --- |
| M0 — Foundation | Day 1 hour 2 | A scaffold → B contracts/platform/placeholder → controlled Firebase configuration | Both build; frozen interface imports; hosted callable smoke check; shared schema examples decode. |
| M1 — First flow | Day 1 hour 7 | B auth/rules/seeds/commands → A resident flows → B queue wiring if needed | Check-in/family update and booking/coordinator queue across real accounts. |
| M2 — Manual operations | Day 2 hour 3.5 | B maintenance/state/assignment/coordinator → A resident session lifecycle | Compatible assignment, helper actions, two distinct confirmations, status/support operations. |
| M3 — Full journey | Day 2 hour 7 | B parser/rewards → A voice/support/wallet → any owner-specific integration fixes | Live voice draft + confirmation, full session, alert/expiry, one monthly award/debit. |
| M4 — Release candidate | Day 3 hour 4 | B hardening/tests → A usability/failure fixes → B sequential deployment | All required checks pass against the integrated release commit. |
| M5 — Handover | Day 3 hour 6 | B runbook/evidence; A supplies screenshots/video links via B | Two reset-to-finish rehearsals, artifacts, known limitations and secure account handoff. |

Dependencies must land before their consumer, or the consumer must use a compiling placeholder until the same checkpoint. Never merge a router import before its widget exists, a new callable name before the backend exports it, or a query before its rules/indexes are ready.

### Change request procedure for shared contracts

- Freeze callable names, field names, enums, wire time/null rules, coordinator widget signature, and shared stream methods at M0.
- If A needs a backend/schema addition, A sends B the task ID, exact field/method, reason, example payload, and affected screen. B owns the schema/backend change; A owns Dart changes.
- If B needs UI support, B requests it from A instead of editing A-owned files. B supplies translation keys/copy in the same request.
- Prefer additive optional fields with backward-compatible defaults. Keep `contractVersion: 1` stable throughout this sprint; avoid renaming/deleting fields mid-sprint.
- Land schema/backend compatibility first, then the Dart adapter, then consumers. Keep the old behavior until every caller is updated. A breaking change needs both developers to stop feature work, agree a coordinated patch, and rerun M0/M1 wire checks.

### Before every PR

- [ ] List task IDs, owned files changed, behavior, checks run, dependent PR/checkpoint, and any new config/index/fixture requirement.
- [ ] Inspect `git diff --name-only origin/main...HEAD` and `git diff --check`. No unagreed cross-owner path, unrelated reformatting, or whole-project regeneration.
- [ ] Resolve contract questions before opening the PR; include one v1 request/result example for API changes.
- [ ] Confirm the branch builds with current `main`; do not rely solely on the two independent branches passing separately.
- [ ] Keep fixtures/mock adapters out of the release execution path; no secrets or account credentials in the PR.

Single-writer paths prevent planned file overlap. They cannot by themselves guarantee behavior: wire examples, incremental gates, and tests on integrated `main` catch semantic conflicts such as different field names, dates, or permission assumptions.

## 8. Fixtures, scheduling, and reward details

### Deterministic demonstration data

B owns fixtures and seeding. A must use the same IDs and JSON shapes for temporary UI work.

| Fixture | Purpose |
| --- | --- |
| Primary elder + consented family + approved helper + active accepted pairing | Main check-in, booking, completion, and monthly reward journey. |
| Second elder with overdue check-in, linked family, coordinator | Missed-alert demonstration independent of the primary elder's successful check-in. |
| Unrelated family, unapproved helper, blocked helper | Authorization and assignment failure cases. |
| Five place records + six future activity records | Access/filter/booking demonstration; use labelled illustrative data. |
| Three historical completed sessions in the selected demo month/pairing | Fourth live session makes monthly award eligible; no per-session coin credit. |
| Fixed mock voucher with server-owned cost, e.g. 100 demo coins | Stable redemption test; award 300, redeem once, resulting balance 200. |

Seed script computes future activity timestamps and compatible helper slots from the chosen demo date/time. It records the chosen month/timezone so UI, reward commands, and tests agree. Historical session fixtures must be distinct and within that selected month. Reset restores all known linked fixture documents, command receipts, reservations, wallet entries, support items, and alerts. It must verify the intended demo project ID before writing/deleting and must never clear a whole shared project.

### Time and expiry behavior

- Check-in states: `pending`, `reminded`, `missed`, `ok`, `paused`. Scheduler reads elder settings even if no daily document exists. Transactions keep daily status and alerts consistent with simultaneous submissions.
- A late `ok` resolves the current daily state while retaining the prior missed-alert event. A resumed app re-reads the server state.
- Place status: `{level, text, updatedAt, expiresAt, setBy}`. Clients stop showing a live warning at expiry and show that status needs review. A visible-screen timer refreshes the banner even if no Firestore snapshot arrives.
- Scheduled cleanup clears old nested status fields; do not use TTL on a place document to expire a nested field. TTL deletes documents and is not immediate; see [Firestore TTL behavior](https://firebase.google.com/docs/firestore/ttl).
- `runDemoMaintenance` reuses the real service with current server time and fixed fixtures. It never accepts an arbitrary date, user, or collection from a resident client.

### Reward correctness

- One 300-coin award per helper per local month, across all their pairings. Four qualifying sessions must belong to the same accepted regular pairing; check on the server.
- Award entry ID is deterministic from helper/month. Credit entry, balance change, and command receipt are written atomically.
- Distinct participant confirmations are mandatory; cancelled, incomplete, or unassigned sessions never count.
- Redemption prices come from server fixture configuration. Debit, entry, voucher code, and retry receipt are atomic. A retry returns the existing redemption rather than debiting again.
- These rules are persisted simulation logic. Phone-call rewards, elder-cancellation exceptions, transfers, milestones, expiry, and real settlement remain unimplemented and must be listed in the handover.

## 9. Verification and deployment gates

### Required checks

| Check | Owner | Minimum cases |
| --- | --- | --- |
| Flutter static analysis/release build | A | All four routes compile; BM/EN resources and coordinator imports resolve. |
| Wire compatibility | A + B | Shared JSON examples decode in Dart and validate on backend; timestamps/nulls/enums match. |
| Auth/rules | B | Unrelated household, withdrawn consent, role tampering, coordinator privilege, helper isolation, immutable wallet/pairing fields. |
| Check-in service | B | Duplicate request, pause, local-day boundary, overdue absent record, late submission, scheduler race/retry. |
| Booking service | B | Compatible pairing, blocked/unapproved/unavailable/overlapping helper, invalid state, separate confirmations. |
| Rewards | B | Four-session eligibility, no partial/cancelled sessions, concurrent duplicate award, repeat redemption, insufficient balance. |
| Client failures | A | Denied microphone, no TTS voice, timeout, stale/offline view, double tap, refresh. |
| AI | B | 20 labelled examples with full-field correctness and clarification recorded; real API call demonstrated. |
| Release smoke/rehearsal | Both | Real hosted origin, separate authenticated sessions, persistence after refresh, two full rehearsals from reset. |

Do not create tests just to mirror widgets or pursue broad coverage. Protect authorization, state transitions, money-like state, and cross-language contracts first.

At foundation, B defines and records these exact package-script interfaces in `functions/package.json`; the runbook must make clear which working directory each command uses:

```text
# From app/; A owns dependency and lockfile changes.
flutter pub get
flutter analyze
flutter test
flutter build web --release

# From functions/; B defines the scripts and owns the lockfile.
npm ci
npm run build
npm test
npm run test:rules
```

`test:rules` starts the needed local emulators against a demo/test configuration and exits after the rules checks. Record actual emulator prerequisites/commands during B01; do not assume they are installed. A test script that silently skips its suite does not satisfy the gate.

### Ordered deployment, B only

1. Record the integrated commit and intended Firebase project/Functions region; confirm required config/secrets exist.
2. Deploy required rules and indexes; wait for new indexes to be ready before the release uses their queries.
3. Deploy backward-compatible Functions and scheduler. Verify one authenticated mutation and one AI parse.
4. Build the Flutter Web release with the matching Firebase project/region. Configure Hosting to serve `app/build/web` with route fallback.
5. Deploy Hosting; hard-refresh a fresh browser session and verify the actual hosted bundle.
6. Seed/reset only the agreed demo fixtures, then run checkpoint smoke checks. Avoid reseeding during another developer's integration run.
7. If a release fails, redeploy the last known-good client/backend commit with the same v1 contract. Preserve ownership of fixes; avoid destructive database resets to hide failures.

Record actual executable deployment commands in the runbook once project IDs/scripts exist. This planning task does not create cloud resources or deploy an application.

## 10. Blockers and controlled scope changes

| Trigger | Action | Delivery status |
| --- | --- | --- |
| Missing toolchain/billing/project access at kickoff | Fix access immediately using Day 1 contingency; continue UI/backend locally where independent. | Hosted goal remains open until deployment succeeds. |
| M0 exceeds hour 2 | Freeze platform expansion; browser only, no FCM/native packaging, no new libraries. | Replan the remaining hours explicitly; do not compress integration to zero. |
| M1 fails at Day 1 close | Stop new UI expansion until persistence/permissions pass; defer wallet redemption UI first if time is lost. | Any removed required goal stays marked incomplete. |
| No reliable live audio by Day 2 hour 4 | Preserve real typed-text → AI draft → confirmation; label prerecorded/sample audio if used. | Live voice G07 is incomplete until a real capture succeeds. |
| M3 fails at Day 2 close | Freeze all additions. Fix the core check-in → booking → completion journey first; defer generic support forms/reward polish as needed. | Record every omitted G-goal; do not call a fixture screen implemented. |
| Day 3 regression fails | Use reserved hours for release blockers; retain last known-good release. | M4/M5 cannot pass on failing authorization or duplicate-credit/debit checks. |

Only after M3 passes may the team spend spare contingency on one optional item: tested FCM, outing goal ring, or family cheer. B owns any new backend/config; A owns UI/dependencies. FCM requires platform-specific credentials/permissions, per the [Flutter FCM guide](https://firebase.google.com/docs/cloud-messaging/flutter/get-started). In-app alerts remain required regardless of push behavior.

## 11. Final acceptance and handover

Mark a goal complete only with an integrated deployed result and the evidence listed below.

| Goal | Final acceptance evidence | Status |
| --- | --- | --- |
| G01 | Hosted URL, deployed callable, persisted result, commit | [ ] |
| G02 | Four account journeys plus negative authorization/rules results | [ ] |
| G03 | Successful check-in/family update; paused/overdue/duplicate cases | [ ] |
| G04 | Activity-linked request persisted and visible to coordinator | [ ] |
| G05 | Cross-session warning update, correct expiry, access filter/Maps link | [ ] |
| G06 | Approved compatible assignment; distinct helper/elder completion; overlap/block failures | [ ] |
| G07 | Live BM/EN recording, validated editable read-back, explicit confirmation, AI results/fallback | [ ] |
| G08 | Fourth qualifying session, one 300 credit, one mock debit, retry tests | [ ] |
| G09 | Trusted support/report inbox and enforced helper block | [ ] |
| G10 | Green release checks, text scaling, two rehearsals, runbook and backup recording | [ ] |

**Five-minute demo:** Saya OK → family update → speak activity request → edit/read-back/confirm → coordinator assigns approved companion → helper accepts/starts → coordinator changes access warning → helper finishes → both participants confirm → family completion → monthly thanks/mock redemption. Show the second elder's overdue alert and support inbox if time permits.

**Handover files B must finish:**

- `docs/CONTRACTS.md`: v1 schema/examples, query/index map, state/permission matrix, signed-off owner map.
- `docs/DEMO_RUNBOOK.md`: prerequisites, commands with working directories, config variable names, seed/reset, account handoff method, demo steps, deployment/rollback, actual URL/commit, delivered/deferred features.
- `docs/AI_EVALUATION.md`: 20-example methodology/results and limitations; no invented accuracy or user-study claims.
- Screenshots/backup recording location supplied by A; share credentials separately from the repository.

The plan and README are documentation changes only. Foundation scripts, app/backend code, tests, cloud setup, and the handover files above are implementation tasks to be completed during the three-day sprint.

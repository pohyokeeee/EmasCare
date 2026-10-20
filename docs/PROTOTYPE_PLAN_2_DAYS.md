# EmasCare: two-person, two-day MVP demo implementation plan

**Status:** Current two-person implementation plan, updated 21 Oct 2026. This replaces the earlier reduced two-day plan. The repository still contains planning documents; application development has not started.

**Team and capacity:** two developers, eight working hours each per day, for 32 person-hours. Allocate 28 person-hours to planned work and four to integration failures and release fixes. Hours below are working hours, excluding breaks.

**Scope basis:** the full EmasCare feature set discussed with the user, including coins, wallet, redemption, light gamification, voice booking, and a coordinator view. Tanya Dulu is future work and is not part of this build.

**Delivery target:** a small, persistent, hosted demonstration of the connected product journey. Every feature family is represented, but some service setup and timing are seeded or operator-triggered as specified below. This is a high-risk stretch target starting from a documentation-only repository; 32 person-hours cannot establish a pilot-ready service or guarantee every full product requirement.

**Platform:** build one responsive **Flutter Web application**. Residents open the hosted URL in a phone browser; the same app opens on a laptop, with more space for the coordinator view. Elder, family, helper, and coordinator are role-specific views within that app. Firebase provides authentication, storage of app data, and backend functions. The presentation includes a mock SDP home/module entry. Native Android/iOS releases and actual SDP app integration are later work. Flutter supports building and serving a browser application; see the [Flutter Web guide](https://docs.flutter.dev/platform-integration/web/building).

**Can this finish in a few hours?** A first milestone in roughly 2-4 elapsed hours with both developers is a planning estimate for the shell, agreed data contract, seeded activities, and potentially one connected check-in flow if the tools/accounts are already ready. A clickable UI can also illustrate more screens using clearly labelled fixture data. That does not finish the complete authenticated booking, consent, voice, coins/redemption, coordinator, and verification work. Keep the two-day schedule as an ambitious demo target; do not promise the full feature set within a few hours.

## 1. Delivery approach and assumptions

Build the complete product story as a small working demo: four thin role views, persisted core actions, protected demo coin accounting, and explicitly labelled seeded/operator-triggered behavior. The current product vision remains the broader destination. Real onboarding/vetting, unattended alerts, complete recurring scheduling, and merchant integrations require a longer schedule. Disclose the demo boundaries in the runbook and presentation.

Assumptions that must hold:

- A already knows Flutter/Dart; B already knows Firebase/TypeScript and can build one simple Flutter coordinator screen. Learning those tools is outside the estimate.
- Both can work for the two days and have a presentation browser/device available at kickoff.
- Use standard Flutter widgets and a single app. Use seeded demo identities, activities, places, accepted trial pairings, and illustrative historical sessions.
- Firebase and AI credentials/project permissions must be available during the first hour. This document does not enable billing, create cloud resources, or authorize a spend.
- Keep one township, one main elder/helper pair, one mock voucher, short BM/EN booking requests, and a small fixed set of activities. Do not add general-purpose editors or a design system project.

## 2. Feature coverage and completion boundaries

**Working** means actions are authorized and persisted, survive refresh, and are visible to permitted accounts. **Seeded** means the setup/history is synthetic. **Operator-triggered** means a coordinator runs a labelled demonstration action; it is not unattended automation.

| Feature | Two-day target | Simplification or boundary |
| --- | --- | --- |
| Four roles and accessible app | Elder, family, helper, and coordinator sign in to their own views; large controls and BM/EN core text. | Mock SDP entry; actual SDP embedding/SSO and native builds are later. |
| Saya OK | Persist today's check-in, separate sharing/booking consent, pause-today, and a coordinator-recorded phone response. Show reminder and missed status in permitted views. | Fixed overdue fixtures and an authorized `processDemoDueItems` action demonstrate escalation. No unattended scheduler or background push is promised. |
| Community activities | Seed a few activities with place, date/time, language, and a companion-request action. | No event creation/ticketing system. |
| Access notes | Show step-free/toilet/seating/walk-time details, a Maps link, and coordinator-set warning with expiry. | Illustrative places; simple client-side expiry handling. No route engine or verified route-safety claim. |
| Family involvement | Permitted daily status, request/session status, and proxy booking using the same booking command as the elder. | Family cannot change consent or confirm the elder's attendance. |
| Recurring neighbour companion | Coordinator sees an accepted regular trial pairing and assigns a compatible available helper from it. Helper can update availability. | Pair and trial acceptance are seeded and labelled. No matching marketplace, vetting integration, or automatic generation of a recurring calendar. |
| Session completion | Assigned helper accepts, starts, and finishes; helper and elder each confirm. Only then is the session completed. | One main session is demonstrated live; cancelled and partially confirmed sessions do not count. |
| Teman voice AI | Short supported BM/EN recording produces an editable booking draft, read-back, and explicit confirmation. A manual form remains available. | Real supported audio and a real API call are the target. No Mandarin/Tamil claim without testing; no concern classifier, AI impact prose, or weekly AI digest in this sprint. |
| Coins and wallet | Coordinator requests a demo monthly eligibility check; backend awards 300 coins once, writes a ledger entry, and updates the helper wallet. | Three historical qualifying sessions are seeded; one live fourth session qualifies. This previews a month-end award using synthetic data. Phone-buddy awards and cancellation exceptions are outside the demo rules. |
| Redemption | One mock voucher costs 100 demo coins; redeem atomically; show remaining balance, history, and the issued item in My Vouchers. | No merchant acceptance, purchase of coins, cash-out, household transfers, donations, expiry, or settlement integration. |
| Light gamification | Weekly outing progress, consented family cheer, helper impact count/card, household give-back count, and a township goal bar. | Simple counts/templates from confirmed synthetic/live sessions; no AI required. A single seeded weekly goal and township target; no goal editor, leaderboard, or streak penalties. |
| Coordinator and reporting | A compact coordinator screen shows pair/request actions, check-in exceptions, place warnings, text reports/block actions, and a small aggregate availability table. | Fixed synthetic dataset; suppress availability groups smaller than five people. No uploads, live research export, full case management, or ratings. |

**Excluded throughout:** Tanya Dulu UI, suspicious-message questions, scam-question voice intents, scam classification, and its human-question inbox. Text place/helper reports are separate existing service features.

## 3. Architecture and dependencies

Retain the repository's planned stack:

- **Flutter Web:** all four role views, responsive phone presentation, BM/EN copy, audio recording/read-back.
- **Firebase Authentication:** seeded email/password accounts. A role comes from the server-owned profile, not a client account-switching flag.
- **Firestore:** role-scoped reads and streams; private settings separate from family-visible summaries.
- **TypeScript callable Cloud Functions:** consent checks, booking transitions, reservations, coin awards, redemption, demo due processing, and AI parsing. Do not put trusted coin or approval logic in the client.
- **Gemini API:** server-side short-audio booking parser. Select a currently supported model/MIME combination during kickoff; keep the API credential out of Flutter.
- **Firebase Hosting:** the static web release. No upload pipeline is needed.

A hosted Cloud Functions deployment requires a Firebase Blaze project; the earlier Spark-only reduced prototype does not meet this architecture. Firebase documents that requirement in its [Functions setup guide](https://firebase.google.com/docs/functions/get-started). If billing/project access is unavailable, a local Emulator Suite demonstration is a possible fallback, but it is not a publicly hosted backend. Record the selected mode at the first checkpoint.

Actual unattended reminder/escalation processing would need a scheduled worker. Firebase's [scheduled-functions guide](https://firebase.google.com/docs/functions/schedule-functions) describes Cloud Scheduler integration. The two-day baseline uses the labelled coordinator trigger; do not present that as a deployed scheduler.

## 4. Ownership: split by experience, with one shared adapter

A is primarily the UI developer, owning the resident experience and shared Flutter code. B is primarily the backend developer, owning server logic/data and the compact coordinator screen. Both integrate and test together. They build against an agreed repository/API contract from the first hour; A does not wait for the entire backend to finish before starting the UI. This keeps Flutter feature development moving while B builds the rules that wallet and booking depend on.

| Area | Developer A | Developer B |
| --- | --- | --- |
| App shell, navigation, widgets, assets, BM/EN text | Owns | Supplies coordinator copy |
| Shared Dart models and `EmasRepository` adapter | Owns; creates compiling method stubs first | Supplies payload examples and reviews semantics |
| Elder and family views | Owns | Supplies authorized data and mutations |
| Helper session and wallet/redeem views | Owns | Supplies lifecycle/reward commands |
| Gamification UI and family-cheer interaction | Owns | Supplies protected writes and progress summaries |
| Voice recording, playback/read-back, draft UI | Owns | Owns audio parsing/validation endpoint |
| Coordinator screen | Registers agreed screen once | Owns screen, reuses A's components/repository |
| Auth/configuration, Firestore rules/indexes, Functions | Reviews visible effects | Owns |
| Fixtures, reset, targeted service/rules checks, deployment | Supplies resident smoke results | Owns |
| Rehearsal, release verification | Joint | Joint |

Suggested file boundaries:

- **A:** `app/lib/app/**`, `app/lib/shared/**`, `app/lib/models/**`, `app/lib/data/emas_repository.dart`, `app/lib/features/elder/**`, `family/**`, `helper/**`, `app/lib/l10n/**`, assets, app dependencies/platform files.
- **B:** `app/lib/features/coordinator/**`, `app/lib/firebase_options.dart`, `functions/**`, `scripts/**`, root Firebase configuration/rules/indexes, data fixtures, backend checks, runbook.
- B exports one `CoordinatorScreen` that receives the repository/session; B does not edit A's router or introduce a second Firebase adapter.
- A owns the Flutter dependency file and lockfile. B owns backend dependencies. Review generated FlutterFire changes together once at foundation.
- Work in separate clones/worktrees with short branches. Agree shared method signatures before branching. Merge adapter/model changes before consuming UI. B deploys only the integrated commit.

## 5. Schedule: 14 planned hours and two reserve hours per developer

The feature rows are stretch targets under the assumptions above. At each checkpoint record what actually works, what is seeded, and what remains incomplete. A screen that only shows a fixture is not a completed persisted feature.

### Day 1: establish the connected journey

| Working hours | Developer A | Developer B | Checkpoint |
| --- | --- | --- | --- |
| 0-1 | Scaffold Flutter Web, register four routes/placeholders, agree repository/models; smoke-test recording and read-back on the presentation browser. | Initialize Firebase/Functions, seed primary identities, verify a callable and an actual audio API request; agree payload examples. | **M0:** compiling shell, agreed contract, infrastructure mode and voice feasibility known. |
| 1-2.5 | Elder Saya OK/settings and family daily-status view, with loading/consent states. | Auth profiles, scoped reads/rules, settings/check-in commands, phone-response action. | A check-in survives refresh and reaches only the permitted family. |
| 2.5-4 | Activity/access cards, manual booking and family proxy form; use the same request command. | Request creation, accepted-pair assignment, availability/reservation checks, session transitions and distinct confirmations. | One manual request reaches the assigned helper. |
| 4-5 | Helper availability and accept/start/finish/confirm actions; wire elder confirmation. | One monthly award transaction, wallet/ledger reads, one voucher redemption transaction. | Completed session and protected reward commands run in the backend. |
| 5-6 | Integrate elder/family/helper flow against real demo data; expose wallet values for the walkthrough. | Deploy backend/rules/indexes and first hosted build with A; fix contract/permission failures. | **M1:** check-in -> request -> assign -> both confirm works across the role views; award/redemption pass authenticated backend smoke calls before their finished UI. |
| 6-7.5 | Record -> editable draft -> read-back -> explicit booking confirmation; manual error fallback. | Audio parsing/validation; begin compact coordinator screen using existing commands. | Real audio target exercised; coordinator can operate the main pair/request. |
| 7.5-8 | Reserve for blockers. | Reserve for blockers. | No new unplanned feature work. |

### Day 2: expose remaining demo features and stabilize

| Working hours | Developer A | Developer B | Checkpoint |
| --- | --- | --- | --- |
| 0-1.5 | Finish wallet, Redeem and My Vouchers; add weekly outing ring and helper impact card. | Finish coordinator actions, text report/block command and UI, and progress-summary calculations. | Wallet and redemption persist; coordinator owns the necessary operations. |
| 1.5-2.5 | Family cheer, household give-back count, township goal bar; connect permitted summaries. | Demo due processor, warning expiry/update, small aggregate availability table and supporting commands. | Every feature family has a connected demo path or a declared gap. |
| 2.5-3.5 | BM/EN core text, large targets, phone/laptop layout, pending/error/insufficient-balance states. | Focused authorization, reservation, completion, award, and redemption checks; fix failures. | **M2:** feature freeze; verify the coverage matrix against actual behavior. |
| 3.5-5 | Joint integration checks; analyze/build release; verify microphone and read-back on hosted origin. | Joint checks; deploy integrated release; verify persisted data across separate accounts. | **M3:** submission candidate and documented limitations. |
| 5-6.5 | Rehearse twice; screenshots and backup recording; verify elder/family/helper scripts. | Reset between rehearsals; verify coordinator script, URL, account handover, fixtures and runbook. | Repeatable submission package. |
| 6.5-8 | Reserve for release blockers. | Reserve for release blockers. | Four reserve person-hours total across both days. |

Do not use the reserve to add more vouchers, places, animations, languages, or new product variations.

## 6. Shared contract to agree during the first hour

Keep one short contract file with sample documents, method parameters/results, and query ownership. Do not create a separate schema/code-generation framework.

### Data needed

| Record | Essential contents |
| --- | --- |
| Profile/household | Auth UID, server-owned role/township/household, linked elder/family IDs. |
| Elder settings and daily status | Separate sharing/booking consent, local due/grace times, pause date; family summary without private reply text. |
| Activity/place | Activity date/time and place ID; access details, Maps link, current warning/expiry. |
| Helper/pairing | Approved/tier/task/language attributes, availability; accepted trial pairing, start/end, cadence. |
| Request/session | Elder, creator, pairing, helper, task/place/activity, time, state, actor-specific confirmations. |
| Wallet/ledger/redemption | Server-owned integer balance; immutable credit/debit entries; voucher price, owner, code and creation time. |
| Notifications/reports/cheers | Authorized recipient/author, related record, minimal text/status, consent requirements. |
| Progress/availability summary | Confirmed outing/helping counts and targets; sanitized cohort counts only. |

### Repository actions

- `signIn`, `signOut`, and scoped streams for the current session and permitted screen data.
- `saveElderSettings`, `submitCheckIn`; coordinator-only recording of a phone response.
- `createRequest`, `assignRequest`, `setHelperAvailability`, and `transitionRequest`.
- `parseVoiceBooking` returning an editable draft and read-back text; it never writes a booking.
- `setPlaceWarning`, `submitReport`, `blockHelper`, and authorized report review.
- `awardDemoMonthlyThanks`, `redeemDemoVoucher`, and own-wallet/redemption reads.
- `sendFamilyCheer` and authorized/sanitized progress-summary reads.
- Coordinator-only `processDemoDueItems`, restricted to the known demo project/fixtures and current server time.

Every mutation derives the actor from Firebase Auth. Use stable submission IDs/idempotency keys, server timestamps and Asia/Kuala_Lumpur date/week/month boundaries. A retry must return an existing result rather than repeat the action.

Session states:

`requested -> assigned -> accepted -> in_progress -> awaiting_confirmation -> completed`

- Coordinator assigns only from an active, accepted, compatible pairing; check approved status, allowed task, availability, blocks and reservation conflicts.
- Assigned helper accepts/starts/finishes. Elder and helper each confirm their own participation. Family cannot confirm for the elder.
- Completion requires both distinct confirmations. Cancellation is allowed before a session starts; it never counts as a completed outing.
- No suitable helper leaves an honest requested/pending state. Show coordinator follow-up rather than silently substituting another helper.

## 7. Coins, redemption and gamification rules

These rules are essential to the requested demo, not decorative UI:

1. Seed three distinct mutually confirmed sessions for the same accepted pair in the selected demo month. The fourth session is completed live.
2. Coordinator runs the labelled **Demo monthly award** action. Backend verifies four qualifying sessions for that pair/month and grants **300 demo coins once per helper per month**, across all their pairs.
3. Write the award ledger entry and balance atomically. Use a deterministic helper/month award identity. More sessions never generate extra monthly awards.
4. The single voucher has a backend-controlled cost of **100 demo coins**. Check funds and create the debit, redemption record/code and retry receipt atomically. A repeated request returns the same voucher; an intentional second purchase uses a new request ID.
5. The main story is **0 -> 300 coins -> redeem once -> 200 coins**, surviving refresh. My Vouchers shows the owned redemption and its demo label.
6. Weekly outing progress counts distinct completed sessions. Seed a goal of two; cancelled, requested or partially confirmed sessions do not count. Saya OK never earns coins or outing points.
7. Only the linked, currently consented family can send/read the related cheer. Repeated taps must not create an accidental flood of duplicate cheers.
8. Helper impact uses factual counts. Household weekend helping and township totals include clearly labelled synthetic history plus live confirmed sessions. Never invent an impact claim from AI wording.
9. The aggregate availability view uses synthetic cohorts of at least five; smaller cells show insufficient data. No individual availability is shown to residents.

Firestore transactions can retry, so transaction callbacks must not issue external vouchers/messages or mutate UI state. Keep the demo voucher issuance inside persisted transaction results; see [Firestore transaction behavior](https://firebase.google.com/docs/firestore/manage-data/transactions).

## 8. Fixtures and demonstration script

B owns one repeatable seed/reset command. It must check the intended demo project and reset only known demo records. Do not wipe a shared database or place credentials in the repository.

Prepare:

- Four main role accounts, a second overdue elder for the exception path, and an unrelated account for permission checks.
- Enough synthetic helper/elder records for the small aggregate view; no real resident data.
- One accepted trial pair, compatible availability, a few upcoming activities/places, one warning, one mock voucher, and the three historical sessions.
- A seeded household weekend-helping history and township/weekly targets so all progress components have an understandable state.
- Demo dates derived from the rehearsal date, avoiding a mismatch between current month and historical reward fixtures.

Main demonstration:

1. Elder signs in through mock SDP entry and completes Saya OK; consented family sees the update.
2. Elder browses an activity and access note; speaks a short booking request, reviews the draft, and explicitly confirms it.
3. Coordinator assigns the accepted trial companion; helper accepts and starts.
4. Coordinator changes a place warning; resident view reflects it.
5. Helper finishes; helper and elder confirm separately; family receives the permitted completion status.
6. Outing/helper/township progress updates; family sends a cheer.
7. Coordinator previews the monthly appreciation award; helper receives 300 coins.
8. Helper redeems the 100-coin mock voucher; wallet shows 200 and My Vouchers shows the redemption.
9. Show the separate overdue elder and labelled due-processing action; coordinator records a phone response. Briefly show the reporting and aggregate-availability panels.

Keep short backup clips of voice and the exception path if the live presentation is interrupted. Label recordings and simulations accurately.

## 9. Checkpoints, failures and honest scope reporting

| Trigger | Required response |
| --- | --- |
| No Firebase/backend access at M0 | Record a local-emulator presentation mode or reduce to an explicitly labelled interactive mock. Do not claim a hosted authenticated backend. The full draft schedule is at risk. |
| Microphone/MIME/model problem at M0 | A checks the actual presentation device while B tests supported short audio. By M1, choose a working supported path or record voice as incomplete. Typed AI parsing can demonstrate the draft flow, but does not complete live voice acceptance. |
| M1 manual flow fails | Use reserve to fix shared contract/state/permissions before adding summary polish. Reassess M2 coverage; do not promise all features have been delivered. |
| Scheduler absent | Keep the operator-triggered due demo label. Unattended reminders/escalation remain unimplemented. |
| Award/redemption check fails | Fix before release. Do not replace protected accounting with client-editable balances or a fake successful redemption. If unresolved, mark the feature incomplete. |
| M2 coverage incomplete | Freeze additions, list the gaps, and deliver the working subset with labelled mock/seeded parts. Meeting the time limit does not make unfinished features complete. |
| Time becomes available | Spend it on failing checks, clarity, or rehearsal. Do not add Tanya Dulu, new integrations or reward variations. |

If every detailed full-MVP requirement must run live, including genuine onboarding and unattended automation, revise the schedule. The two-day fallback is a smaller demonstrator, not an equivalent operational product.

## 10. Acceptance and handover

Focused checks protect behavior across accounts and retries; extensive widget/unit coverage is not the goal of this sprint.

- [ ] Four role journeys use actual authenticated identities; unrelated accounts cannot read another household or use coordinator actions.
- [ ] Check-in persists; sharing withdrawal blocks family status/history and relevant notification reads; booking withdrawal blocks proxy requests. Family cannot edit either setting.
- [ ] One request produces one session across double taps/retries; two competing assignments cannot reserve the same helper.
- [ ] Helper cannot act on another helper's request. One-sided confirmation, cancellation and incomplete sessions do not qualify for progress or rewards.
- [ ] Repeat/concurrent monthly awards credit once. Repeat redemption debits once. Insufficient balance rejects without issuing a voucher. Refresh preserves wallet and owned voucher.
- [ ] Seeded regular pairing/trial, mock vouchers and operator-triggered due processing are labelled; no unavailable helper or expired warning is presented as successful/safe.
- [ ] Cheer and progress reads respect consent/role boundaries; no coin award for check-ins; aggregates suppress small cohorts.
- [ ] Actual BM/EN audio -> validated editable draft -> spoken read-back -> explicit confirmation is demonstrated on the presentation device, or the precise gap is listed. Denied microphone/API failures preserve manual booking.
- [ ] `flutter analyze` and `flutter build web --release` pass; B's focused backend/rules checks pass.
- [ ] Two rehearsals complete from reset using separate authenticated accounts; one includes the coin/redemption flow.
- [ ] Hosted URL or explicit local-demo instructions, integrated commit ID, secure account handover, reset command, screenshots/backup recording and a working/seeded/operator-triggered/incomplete feature matrix are ready.

The final handover must distinguish the demonstrated product story from real service operations. Pilot readiness still needs resident onboarding/vetting, genuine recurring scheduling, unattended follow-up, real SDP/merchant integration, and broader device/language validation.

## Technical references checked for this draft

- [Firebase Functions setup and deployment prerequisites](https://firebase.google.com/docs/functions/get-started).
- [Firebase scheduled functions](https://firebase.google.com/docs/functions/schedule-functions).
- [Firestore transaction behavior](https://firebase.google.com/docs/firestore/manage-data/transactions).
- [Gemini audio input](https://ai.google.dev/gemini-api/docs/audio): supports short audio input; validate model, MIME, limits and device capture at kickoff. API credentials stay on the backend.

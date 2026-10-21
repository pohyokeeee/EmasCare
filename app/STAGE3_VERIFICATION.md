# Phase 3: live booking and session integration

Implemented on `ui-phase-3`, from merged main `adb1b63`. Developer A owns the Flutter changes. B's backend includes Stage 3 and subsequent Stage 4; this UI change connects the agreed Stage 3 flow. No backend Functions, rules, indexes, scripts or deployment configuration are changed. No commit or push has been requested for this phase.

## Implemented behavior

- `setHelperAvailability`: helper saves their availability and weekly MYT intervals, including multiple intervals and full-day end 24:00. Local validation rejects malformed or overlapping intervals; approval, tier, languages and allowed tasks remain server-owned. Existing commitments remain visible.
- `createRequest`: actual elder or currently booking-consented linked family submits a reviewed request. Activity requests use the exact catalogue place and entire scheduled interval. Standalone in-person help selects a recorded place; phone help sends explicit null activity/place IDs. Only supported task/language/gender fields are sent; preview-only notes stay out of live payloads.
- `assignRequest`: same-township coordinator selects an active mutually accepted pairing for the requested elder. The backend validates task/tier, language/gender, trial/cadence, availability, blocks and reservations. Stable errors explain unavailable or conflicting assignments.
- `transitionRequest`: assigned helper accepts, starts and finishes; timing gates are shown in the UI and enforced by the backend. Elder/helper confirm only their own participation. Both confirmations are required for completion. Elder, permitted family and coordinator can cancel in the supported early states.
- Role-scoped request streams update the UI and restore saved records after refresh. Coordinator selects one server queue state. Family requests follow current booking consent independently of daily sharing. Consent/scope loss cancels streams, clears private records/retry state and closes affected forms/dialogs.
- One frozen payload and idempotency key per confirmed action, retained across retries and protected against duplicate taps. Replayed callable results cannot overwrite newer stream state. Pending actions can be retried from their form or workspace; stopping a retry does not cancel an already saved booking.
- Existing design preview stays separate and labelled. Live actions never fall back to samples. BM/EN, responsive navigation, larger text, reduced motion, solid navigation and existing critically damped press feedback are preserved.

All mutations go through B's callables with `contractVersion: 1`. The server owns identity/authorization, recorded timestamps, state and completion IDs. The UI uses requested schedule timestamps only. Participants' completion claims remain `pending_policy`; no coins or wallet entries are invented.

## Files to review

| Source | Purpose |
| --- | --- |
| `lib/models/session_models.dart` | Exact request states, lifecycle dates and participant confirmations, with Firestore/ISO timestamp normalization |
| `lib/data/session_repository.dart`, `lib/data/firebase_backend_repository.dart` | Typed Stage 3 callables and exact scoped queries |
| `lib/app/session_workflow_controller.dart`, `lib/app/preview_controller.dart` | Auth/consent scope binding, pending actions, frozen retries and scheduled-action boundaries |
| `lib/features/community/live_request_form.dart` | Supported request fields and review/send |
| `lib/features/community/live_availability.dart` | Helper weekly hours editor |
| `lib/features/community/live_session_workspace.dart`, `session_ui.dart` | Live requests, assignment, lifecycle, confirmation and feedback |
| Existing community/connected views and shell | Live routing, permission-aware sheets and current feature copy |
| `web/firebase_local.mjs`, `tool/firebase_bootstrap.test.cjs` | Auth emulator connects immediately, then finishes initial restore before FlutterFire startup |
| `test/stage3_test.dart`, `test/phase2_test.dart` | New live-flow coverage and consent-close regression |

## Verification record — 22 October 2026, Malaysia

- Final source analysis and regression check: **56 Flutter tests passed**, five browser-device bridge tests and two Firebase bootstrap tests passed; analyzer clean.
- Backend TypeScript build and **11 unit tests passed**.
- **66 backend integration/rules checks passed** against the existing local Auth/Firestore/Functions emulators, including all Stage 3 and Stage 4 regression scenarios. These use/reset disposable demo fixtures.
- The final source release web build passed. The rebuilt app was opened in fresh browser sessions and loaded the saved completion, cancellation and availability state.
- Widget coverage includes exact payload fields/activity intervals, ISO/Firestore timestamps, deep-frozen retries, duplicate taps, stale responses, role/queue scopes, independent booking consent, withdrawal/restoration, availability overlap/full-day hours, standalone phone IDs, cancellation, timed start/finish and distinct confirmations. Live cards and request/review sheets were checked in BM/larger text at 320/390/768/1440 widths.
- Browser startup exposed an initial Auth restore race. The bootstrap now awaits readiness after connecting the emulator and before FlutterFire initialization. Fresh sign-ins on the final build succeeded.
- Real browser acceptance used separate elder, family, coordinator and helper sessions: elder activity request, permitted family visibility, coordinator assignment, helper acceptance and a disabled start before the scheduled activity time. The ready phone-help request went through accept/start/finish, then separate helper and elder confirmations. The first confirmation left it incomplete; the second produced **Confirmed by both** for all permitted readers.
- Real browser checks also covered saving/unavailable weekly hours and refresh, a rejected assignment while unavailable, restoring availability and retrying the retained action successfully, cancellation, and booking-consent withdrawal/restoration. Withdrawing booking closed the family's open form and cleared requests while daily sharing stayed on; restoration returned saved requests without reopening the old draft.
- A regression test reproduced a slower-response assignment race: a request can leave the coordinator's filtered queue before its callable reply arrives. The retry now closes the owning sheet correctly, and a dismissed sheet cannot navigate after the reply. Both orderings pass in the final 56-test suite.
- A fresh unrelated-family sign-in on the final build showed no linked elder or private requests and a disabled New request action. The final helper and unrelated-account browser sessions recorded no console errors. BM, larger text, gentler motion and solid navigation were visually checked in the real phone availability editor.
- A read-only authenticated emulator check confirmed both saved participant UIDs, the final-confirmation completion timestamp, separate `pending_policy` claims, zero wallets and no ledger entries. Helper availability was restored to available with full-day intervals. The demo now retains a completed ready phone-help session, an accepted future Garden walk, and a cancelled family-created phone-help request.

Screenshots: [completed real session](preview/stage3-completed.png), [BM phone availability with larger text](preview/stage3-phone-bm.png), [waiting for the elder's confirmation](preview/stage3-awaiting-confirmation.png), [family consent withdrawn](preview/stage3-consent-withdrawn.png), [unavailable companion feedback](preview/stage3-assignment-unavailable.png), [unrelated family access](preview/stage3-unrelated-account.png).

Repeat the frontend checks with `app/preview.ps1 -Mode check` and `app/preview.ps1 -Mode build`. Backend regression verification used `npm.cmd run build`, `npm.cmd run test:unit` and `npm.cmd run test:integration` against the already-running local suite. The integration command resets disposable demo fixtures; run it before a manual walkthrough, not while preserving a demonstration in progress.

## Local startup

Keep the existing emulators and preview server running if they are already available. Full first-time setup is in [LOCAL_BACKEND.md](LOCAL_BACKEND.md).

```powershell
# Repository root, only if the emulators have stopped:
$env:JAVA_HOME='C:\Users\user\.jdks\openjdk-25.0.1'
$env:FUNCTIONS_DISCOVERY_TIMEOUT='60'
$env:FIREBASE_EMULATORS_PATH=Join-Path (Get-Location).Path '.cache/firebase/emulators'
npm.cmd run emulators

# Separate terminal; resets disposable demo data:
npm.cmd run demo:reset

# App terminal:
cd app
.\preview.ps1 -Mode build
# Start only if 8090 is free:
.\preview.ps1 -Mode serve
```

Open `http://127.0.0.1:8090`. Existing preview servers serve a newly built release after reload. Firestore owns 8080. All demo accounts use `EmasCare-local-2026!`; use separate tabs for `elder@emascare.test`, `family@emascare.test`, `helper@emascare.test` and `coordinator@emascare.test`.

## Manual acceptance walkthrough

1. Elder → Activities → Garden walk → Request a companion → Review → Send. The full activity schedule/place are fixed. My companion shows **Awaiting coordinator**. Refresh and confirm the request remains.
2. Family → My companion. The same request is visible with booking consent on. Family can create/cancel permitted requests but has no participant-confirmation button.
3. Coordinator → Requests → Awaiting coordinator → Choose companion → Assign. The requested row leaves this queue; select Awaiting helper to see the saved assignment.
4. Helper sees the assignment and accepts. A future activity's Start button stays disabled until its start; Finish stays disabled until activity end. Use the backend timing tests for those future boundaries.
5. For an immediate real completion, use the separately seeded **assigned phone-help** request `request_demo_ready`. Helper accepts → starts → finishes → confirms. It must still await the elder. Elder confirms separately; both sessions update to **Confirmed by both**. No coin balance changes.
6. Helper → Edit availability: save hours/available state, refresh and verify saved values. Existing sessions stay visible when unavailable. A new incompatible assignment reports the backend's reason and preserves request state.
7. Elder settings → turn off family booking, keep daily sharing on and save. Family requests disappear and any open request form closes. Daily status remains separately permitted. Restore booking; saved requests return, with the old unsent form still closed.
8. Cancel a fresh early-state request and confirm it remains cancelled after refresh. Sign in as unrelated family: no linked elder or request data is shown. Check BM/EN and phone accessibility controls.

## Remaining product boundaries

Local emulators only; no cloud deployment. Reward policy/coin credit/redemption, voice/AI, automatic reminders/notifications and Stage 4 standalone-attendance UI remain outside this change. A genuinely future activity cannot be rushed through real timing gates; the ready phone-help fixture enables an immediate lifecycle rehearsal without a backdating API.

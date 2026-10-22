# Phase 4: activity attendance integration

Implemented on `ui-phase-4`, based on merged main `d3bd841`. Developer A owns this Flutter integration. Backend Functions, rules, indexes and scripts remain unchanged. No cloud deployment is included.

## What users can do

- Elder Activities → Past activities: open a finished in-person activity and press **I attended**. The saved status is **Awaiting verification**, without coins or verified participation yet. Future/online activities cannot be submitted. A companion-managed activity directs the elder to the existing session confirmations instead.
- Coordinator Requests → Attendance review: review the same-township submitted queue. Verification requires a trusted method (personally observed or organizer roster) and a factual note; rejection requires a reason and sends a null method. Notes are trimmed and limited to 1–500 characters. The review is final, and saved records leave the submitted queue.
- Elder/Family Activities → Attendance history: read saved pending, verified and unverified attendance, review notes, methods and dates. Family needs current daily-sharing consent for the selected linked elder; booking consent is independent. Family/helpers cannot submit or review for an elder. Helpers have no standalone-attendance history stream.
- All successful mutations use B's version 1 callable envelopes and server-owned identities/timestamps. Immutable action payloads and keys survive retries; duplicate taps are ignored. Streams remain authoritative over old receipt responses. Scope/permission loss clears records, commands and open review drafts. An early queue update cannot strand a successful review sheet or navigate a previously dismissed one.

The existing warm white/forest green Manrope design, immediate critically damped press feedback, accessible sheets, BM/EN, larger text, gentler motion and solid navigation are retained. End-time boundaries update activity eligibility while details stay open. The SDK's fixed emulator banner no longer blocks phone navigation; local-demo labels remain throughout the app.

## Changed-file guide

| File | Purpose |
| --- | --- |
| `lib/models/attendance_models.dart` | Complete Stage 4 records, nullable review/completion fields, Firestore/ISO timestamps |
| `lib/data/attendance_repository.dart`, `firebase_backend_repository.dart` | Two attendance callables and exact elder/family/coordinator scoped queries |
| `lib/app/attendance_controller.dart`, `preview_controller.dart` | Auth/sharing scopes, immutable retries, stream authority and cleanup |
| `lib/features/community/attendance_views.dart` | Submission/status/history, coordinator queue/review and guarded sheets |
| `lib/features/community/activity_catalog.dart`, `lib/features/connected/connected_home.dart` | Past/history entry points and coordinator request tabs |
| `lib/app/community_controller.dart`, `lib/data/backend_failure.dart` | Activity-boundary updates and stable localized errors |
| `web/firebase_local.mjs`, `tool/firebase_bootstrap.test.cjs` | Unobstructed local preview navigation with the same initialization/origin guards |
| `test/stage4_test.dart` | Fixture, authorization/scope, consent, retry, race, timing and responsive tests |
| `tool/verify_attendance.mjs` | Read-only six-account emulator query/privacy checks, optional saved-browser-result assertions |

## Verification — 22 October 2026 (Malaysia)

Final-source check passed: analyzer clean, **72 Flutter tests**, five browser-device bridge tests and two Firebase startup tests. The final release build passed (127 seconds on this run). Backend build, **11 unit tests** and **66 integration/rules tests** passed, including all 14 Stage 4 scenarios. Browser acceptance completed against the local Auth/Firestore/Functions emulators.

The 16 added Flutter tests cover complete fixture parsing, submission keys and duplicate taps, immutable review retries, authoritative newer stream state, sharing versus booking, helper/unrelated denial, permission cleanup, late logout responses, selected-elder changes, both review decisions, future/online and companion-managed activities, exact end-time eligibility, both review-reply/queue orderings and dismissed sheets, open-review permission loss, and BM/larger-text layouts at 320/390/768/1440 widths.

Actual browser results:

- Main elder submitted the seeded past activity for themselves. Family history and the coordinator queue updated automatically. Empty method/note validation prevented an incomplete review; a saved organizer-roster review closed the sheet, removed the submitted queue item and updated elder/family history to verified with the saved note.
- Booking off with sharing on retained family history. Sharing off with booking on cleared family records and notes immediately. **22 read-only checks passed while sharing was off**, including fresh denied server reads. Restoring sharing restored the history. Both consents are on in the final demo.
- Reloading elder/family/coordinator preserved sign-in and saved server state. The final build was checked in English and BM, including larger text, gentler motion, solid navigation and unobstructed phone navigation. Preferences were restored to English/defaults afterward.
- The solo elder submitted separately. Coordinator rejection saved a reason with no verification method; the solo elder saw the final Not verified record without a resubmission action. An unrelated family account saw no linked elder/history; a helper had no standalone-history or submission action.
- The existing ready phone session still required distinct helper and elder confirmations and completed after both. Its saved-result verifier passed; both claims remained pending policy and balances/ledgers stayed zero. Phone help created no standalone activity attendance.
- The six-account attendance verifier passed **26 read-only checks**, including both saved review outcomes, scoped queries and denials, pending claim metadata, zero coins and reviewed-record removal from the submitted queue. It passed again after the extra pending Garden walk submission described below. All three final browser sessions had no captured console errors.

Screenshot evidence: [verified family history](preview/stage4-verified-history.png), [BM phone with larger text](preview/stage4-phone-bm.png), [sharing withdrawn](preview/stage4-sharing-private.png), [coordinator review form](preview/stage4-review-form.png), [rejected solo history](preview/stage4-rejected-history.png), and [unrelated family account](preview/stage4-unrelated-account.png).

## Ready-to-try demo state

The preview is at `http://127.0.0.1:8090`, with elder, linked-family and coordinator tabs left open. **Garden walk**, ending at 10:00 MYT on 22 October, was submitted by the main elder at 10:12 MYT and is intentionally awaiting verification. Open coordinator **Requests → Attendance review → Review attendance** to try the remaining review yourself using an explicitly synthetic demo note. The elder and family history show the pending record automatically.

The main elder's Past community activity (demo) is already verified with the note “Verified against the synthetic demo organizer roster.” The solo elder's separate record is rejected with “Not listed in the synthetic demo organizer roster.” Reviews are terminal. These give examples of all three statuses without resetting. The ready phone session is completed with two confirmations. No coins were issued. Avoid `demo:reset` if you want to retain these examples; it clears disposable walkthrough records and may invalidate sign-ins.

## Start and try locally

Use the existing running suite/preview when available. Full first-time setup is in [LOCAL_BACKEND.md](LOCAL_BACKEND.md). For a stopped suite, from the repository root:

```powershell
$env:JAVA_HOME='C:\Users\user\.jdks\openjdk-25.0.1'
$env:FUNCTIONS_DISCOVERY_TIMEOUT='60'
$env:FIREBASE_EMULATORS_PATH=Join-Path (Get-Location).Path '.cache/firebase/emulators'
npm.cmd run emulators
# Separate terminal, for a fresh disposable demo:
npm.cmd run demo:reset
# App terminal:
cd app
.\preview.ps1 -Mode build
# Only if 8090 is free:
.\preview.ps1 -Mode serve
```

Open `http://127.0.0.1:8090`. All demo passwords are `EmasCare-local-2026!`. Use separate tabs for elder, linked family and coordinator. Reset can invalidate an existing sign-in; sign in again after a reset. Avoid resetting while preserving a walkthrough.

1. `elder@emascare.test` → Activities → Past activities → Past community activity (demo) → I attended. Confirm Awaiting verification and no second submit action.
2. `family@emascare.test` → Activities → Attendance history. The submission appears while sharing is on. Family has no submission/review action.
3. `coordinator@emascare.test` → Requests → Attendance review → Review attendance. Saving without a method/note must fail inline. For this synthetic fixture only, select organizer roster, record a note explicitly describing demo evidence, and Save review. The sheet closes and the record leaves the queue; elder/family show the verified record and note.
4. Refresh elder/family, reopen Attendance history and verify saved state. Turn booking off but leave sharing on: history remains. Turn sharing off while booking is on: family records and notes clear. Restore sharing: saved history returns.
5. `solo@emascare.test` submits the same past activity for themselves. Coordinator chooses Cannot verify and writes a reason. The solo elder sees Not verified and the saved reason, with no resubmission button or verified effects.
6. Check helper/unrelated-account boundaries, BM/EN, larger text/reduced motion/solid navigation, and phone/desktop views. Existing companion activities use their session confirmations; future activities cannot be rushed through timing gates.
7. From the repository root, run `node app/tool/verify_attendance.mjs --expect-browser-results`. This expects the main elder's verified past attendance and solo elder's rejected attendance. It checks saved review metadata, distinct permissions, pending-policy claim, zero wallet/ledger changes and removal from the submitted queue without writing data.

## Repeat checks

```powershell
# app/
.\preview.ps1 -Mode check
.\preview.ps1 -Mode build
# root, existing emulators (resets disposable fixtures):
npm.cmd run build
npm.cmd run test:unit
npm.cmd run test:integration
# root, read-only:
node app/tool/verify_attendance.mjs
```

Verified/rejected review outcomes are terminal under the current backend. Coordinator records expose an elder reference rather than a display name; the UI shows that reference without inventing a name or broadening the documented attendance queries. Claims remain pending policy. Rewards/redemption, voice AI, aggregate reports and cloud hosting are outside this phase.

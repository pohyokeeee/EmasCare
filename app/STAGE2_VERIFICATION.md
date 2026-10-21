# Flutter Stage 2 verification — 21 October 2026

Branch: `codex/flutter-checkins-integration`. Base: merged `origin/main`, `f64fc02` (backend Stage 2 PR #3). The results below record the completed integration checks; the project owner also reported that their overall manual testing passed.

## Automated checks

| Check | Observed result |
| --- | --- |
| `app/preview.ps1 -Mode check` | Passed |
| Flutter analyzer | No issues |
| Flutter tests | 23 passed (15 connected/backend-focused, 8 existing preview tests) |
| Browser device bridge tests | 5 passed |
| Firebase JS startup-order tests | 2 passed |
| Flutter Web release build | Passed, including the release Auth restoration fix |
| `npm.cmd run test:unit` | 8 passed |
| `npm.cmd run test:integration` against running local emulators | 36 passed; no failures |
| `git diff --check` | Passed |
| Diff of backend Functions, rules, indexes, scripts, Firebase config and root package files | Empty |

The backend tests exercised real sign-in/callables, listener revocation, independent consent, cross-township and unrelated-account denial, pause/app/phone behavior, concurrent submissions, idempotency replay, rollback, Malaysia date boundaries and direct-write/financial privacy denials. Expected permission-denied logs are negative test cases.

Flutter checks cover strict role routing, stale auth completion after sign-out, frozen retry payloads/keys, duplicate taps, authoritative streams, timestamp/envelope parsing, immediate clearing/cancellation on withdrawal/permission denial, unlinked families and empty query state. Connected BM/larger-text layouts were checked at 320, 390, 768 and 1440 pixels across all roles. Existing preview tests also cover every role/destination at those widths.

## Observed browser journey

Used independent tabs and actual seeded accounts against Auth 9099, Firestore 8080 and Functions 5001; Flutter was served at 8090.

- Elder signed in with its server profile and submitted Saya OK. Elder and family showed the same saved OK time.
- Sharing was withdrawn with booking left enabled. The active family view removed its success/time and showed private status while booking consent remained on.
- Sharing was restored with booking disabled. Family status returned and booking consent remained off, including after refreshing the family session.
- Elder refresh retained the authenticated session, original submission time and saved consent. A release-only FlutterFire initialization issue was identified and fixed by synchronously connecting the Auth emulator before persisted-user restoration. The pinned public JS SDK and FlutterFire initialization dependencies/options match; regression tests cover initialization ordering/configuration.
- Standalone elder saved a paused day and changed grace minutes. Saya OK was disabled, pause survived refresh, and the coordinator's exception query excluded that day.
- Unpausing and saving due time `00:00` / zero grace returned the elder to the coordinator's overdue list.
- Coordinator confirmed a synthetic phone report. Its exception row disappeared and the standalone elder received the saved OK state. The confirmation explicitly explains that no telephone call is initiated.
- Family sign-out removed the private view. Unrelated family signed in and showed no linked elder or daily status.

After the initial verification, demo fixtures were reset for a fresh walkthrough and emulator/preview terminals were left running for local review. See [LOCAL_BACKEND.md](LOCAL_BACKEND.md) for exact startup and manual steps, including handling already-running services.

The initial review screenshot shows the demo elder with a fresh, unsubmitted day. [Connected elder screenshot](preview/stage2-connected-elder.jpg).

## Files and ownership

- App wiring: `lib/main.dart`, `lib/app/emas_app.dart`, `lib/app/preview_controller.dart`, `lib/app/app_shell.dart`; new `firebase_bootstrap.dart` and `session_controller.dart`.
- Backend adapter/models: new `lib/data/backend_repository.dart`, `firebase_backend_repository.dart`, `backend_failure.dart`, `lib/models/backend_models.dart`; fixture-model comment clarified in `preview_models.dart`.
- Connected UI: new `lib/features/auth/sign_in_screen.dart` and `lib/features/connected/connected_home.dart`; `role_views.dart` dispatches connected mode.
- Web/runtime: `pubspec.yaml`, `pubspec.lock`, `web/index.html`, new `web/firebase_local.mjs`, `preview.ps1`, `tool/serve.cjs`.
- Tests/handover: new `test/backend_test.dart`, `tool/firebase_bootstrap.test.cjs`, `LOCAL_BACKEND.md`, this record; app/root README updated. Screenshots live in `preview/`.

## Limits

This is a local emulator integration. First browser SDK loading requires internet access. No hosted/cloud deployment or production-index readiness was tested. Retry intentions live in memory until success/cancellation; refresh reloads saved domain state. Firebase JS pre-initialization must be reviewed alongside future FlutterFire upgrades.

Booking, availability mutations, sessions, rewards/redemption, automatic due processing/reminders/notifications, AI voice and Tanya Dulu remain outside this stage. Connected destinations identify pending functionality; explicit design-preview mode uses labelled fixtures. Check-ins award no coins. No backend implementation files were changed.

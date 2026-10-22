# Stage 6: connected coordination, progress and voice fallback

Delivery branch: `ui-phase-6`; integration was developed against merged main `66c4854`. Developer A owns this Flutter integration. No backend Functions, rules, indexes, backend scripts or reward policy were changed by the UI work. The owner authorized committing, publishing and merging this branch through a pull request. No cloud deployment is included.

## Connected features

- **Updates:** saved recipient/elder/consent-scoped notifications, unread state and persisted mark-read. Families have separate sharing and booking subscriptions. Consent/profile changes cancel affected subscriptions and clear private views; late responses cannot restore them.
- **Progress & community:** current week/month elder outings, helper sessions, household give-back and authorized township totals. The backend owns targets and classifications. Phone help remains outside outings, while two existing sitting/carrying participations await an outing definition. These still earned their approved coins. Illustrative history and synthetic availability are labelled; groups below five remain hidden.
- **Reports & places:** reviewed/confirmed problem reports, the creator's currently permitted history, coordinator seen/done review, warning update and explicit clear. Expiry retains the warning and means coordinator review is needed. It never certifies a place safe.
- **Coordinator tools:** saved check-in/request/attendance/report/warning summaries, manual due-item processing and blocking of a recorded companion. Blocking prevents future assignment/acceptance/start; it does not cancel an existing session. There is no unblock API.
- **Family cheers:** once per family member and verified outing, with a saved elder notice and no coins.
- **Voice / text booking:** explicit microphone start, a 30-second/1-MiB capture limit, actual container MIME, cleanup on cancel/denial, server parser and a separate user confirmation through the existing booking API. Manual booking remains available throughout. The user chose the disabled-provider fallback for this delivery; no live Gemini/audio success is claimed.

All mutation inputs carry contract version 1 and one frozen action key/payload across retries. Read/parser inputs omit the mutation key. Domain writes use callables. Callable ISO strings and Firestore timestamps are normalized consistently.

## Files

| Area | Files |
| --- | --- |
| Models and adapter | `lib/models/coordination_models.dart`, `lib/data/coordination_repository.dart`, `lib/data/firebase_backend_repository.dart` |
| Scope, subscriptions and retries | `lib/app/coordination_controller.dart`, `lib/app/preview_controller.dart` |
| Connected screens/forms | `lib/features/coordination/coordination_view.dart`, `voice_booking_view.dart`, `features/connected/connected_home.dart` |
| Warning retention, labels and errors | `lib/features/community/activity_catalog.dart`, `lib/app/app_shell.dart`, `lib/data/backend_failure.dart` |
| Browser audio adapter | `lib/platform/browser_web.dart`, `browser_stub.dart`, `web/voice_bridge.js`, `web/index.html` |
| Verification | `test/stage6_test.dart`, updated expiry regression in `test/phase2_test.dart`, `tool/voice_bridge.test.cjs`, `tool/verify_coordination.mjs`, `preview.ps1` |

## Verified on 22 October 2026

- Backend TypeScript build and **24 combined unit checks** passed after pulling B's Stage 6 merge.
- Flutter analyzer: **no issues**. All **98 Flutter tests** passed, including ten new Stage 6 tests. Coverage includes independent consent withdrawal, late auth/parser replies, immutable retries, duplicate taps, wrong-owner streams, separate voice confirmation, unavailable-provider/manual fallback, report confirmation and BM/larger-text layouts at 320/390/768/1440 widths across all roles.
- All **13 browser/device/startup checks** passed: five original device checks, two Firebase startup-order checks and six new voice bridge checks.
- Release web build passed. The final rebuild includes the updated connected-feature footer.
- The six-account read-only verifier passed **104 Stage 6 checks**: exact report/notification queries, safe progress projections, summary suppression, private configuration denial, unrelated-family denial and role permissions. Live testing found that linked reports require explicit elder and household filters as well as request/creator/township; the adapter and verifier now include them.
- Authenticated local API walkthrough passed report create/same-key replay/seen/done/persistence, unrelated read denial, solo/helper block and family block denial, safe outing projection and cheer uniqueness, actual `VOICE_SERVICE_UNAVAILABLE`, repeat due processing without duplicate notices, preserved first read time, retained expired warning/needs-review count/explicit clear, and independent sharing/booking withdrawal. Both family consents were restored.
- Reports, warnings, blocking, cheers and parser attempts left earned wallets unchanged: **elder 20 coins, helper 0 coins**. Their previous 20-coin credits, 100-coin demo redemptions and completed sessions were preserved. No artificial opening balance or completion was seeded.
- After restoring the emulator export, all **104 Stage 6 checks** and **62 earned-wallet checks** passed again. Connected browser verification passed fresh elder/family/coordinator sign-in, saved check-in restoration, a new report and coordinator seen/done review, saved cheer/progress, sharing withdrawal closing the private progress sheet, independent booking withdrawal hiding requests, and restored consents. Screenshots: [family progress](preview/stage6-family-progress.png), [sharing withdrawn](preview/stage6-sharing-withdrawn.png), [coordinator read notification](preview/stage6-coordinator-updates.png).

The first parallel emulator startup exceeded its worker discovery allowance while local memory was low. Failed workers were stopped. Auth/Firestore were exported to the ignored `.cache/phase6-preserved-20261022` directory, then restored with a 120-second discovery allowance and sequential Functions execution (`--inspect-functions=9229`, loopback only). This runtime workaround does not change backend source or prove parallel emulator timing. Do not reset the current walkthrough to recover from a temporary connection failure.

## Start and try

If the services are already running, open **http://127.0.0.1:8090**. Firestore owns 8080. Full Windows setup and demo accounts are in [LOCAL_BACKEND.md](LOCAL_BACKEND.md).

For a fresh disposable run, use three terminals:

```powershell
# Terminal 1, repository root
$env:JAVA_HOME='C:\Users\user\.jdks\openjdk-25.0.1'
$env:FUNCTIONS_DISCOVERY_TIMEOUT='120'
$env:FIREBASE_EMULATORS_PATH=Join-Path (Get-Location).Path '.cache/firebase/emulators'
npm.cmd run emulators

# Terminal 2, root; only for a fresh run, since reset removes saved examples
npm.cmd run demo:reset
npm.cmd run demo:configure-rewards

# Terminal 3
cd app
.\preview.ps1
```

Wait for all Functions definitions to load. If a first cold profile request times out, wait for the runtime to become ready, then use **Retry profile**. Avoid repeated overlapping retries during cold startup. On a memory-constrained local run, the Firebase CLI's optional `--inspect-functions=9229` flag runs functions sequentially. Keep its inspector on loopback. The current restored run uses this mode. Export/import retains saved data; `demo:reset` does not.

All demo accounts use `EmasCare-local-2026!`. Use `elder@emascare.test`, `family@emascare.test`, `helper@emascare.test` and `coordinator@emascare.test` in separate tabs. `solo@emascare.test` and `unrelated@emascare.test` cover isolated/denied access.

1. Elder → **Reports & places** → **Report a problem**. Choose a place, describe a clearly labelled demo issue, review, then confirm. Coordinator → **Reports & places** → mark it seen/done. Refresh the elder view: its saved review state remains.
2. Coordinator → review/update a place warning, enter a future **MYT** time using `YYYY-MM-DD HH:mm`, review and save. Residents see the warning. After expiry, refresh: it still appears and needs review. Clear it only after an explicit coordinator review. The original garden demo warning is retained; the API smoke test explicitly cleared only its temporary hall warning.
3. Coordinator → **Coordinator tools** → process due check-ins. Inspect **Updates**, then mark a notice read. A second processing run creates no duplicate notices. This is an in-app manual demo action, not a scheduler, push notification or phone call.
4. Family → **Progress & community**. The existing elder has three verified outings and two sitting/carrying participations awaiting classification. One saved cheer is shown without another coin award. The six-member synthetic availability group is visible; the three-member group is suppressed. Township resident counts are separately suppressed because fewer than five elder profiles exist.
5. Elder → turn sharing off while leaving booking on, save. Family must clear status/progress/cheers/sharing notices while permitted bookings remain. Restore sharing, turn booking off and save: sharing returns, booking requests/notices disappear. Restore both after testing.
6. Elder or booking-consented family → **My companion** → **Voice / text booking**. Enter a synthetic request → **Prepare draft**. With Gemini disabled, expect the configuration message and **Use manual booking**. The manual form is the existing connected request form. No parser fixture is shown as a live success.
7. Try **BM**, larger text, gentler motion and solid navigation. Refresh and sign out/in to check saved state and privacy cleanup. Elders/helpers retain **My rewards**; family/coordinator have no spending interface.

The live smoke test blocks `helper_demo` for `elder_solo` only. The main elder/helper pairing remains available for the user walkthrough. The UI block form is limited to recorded pairings; broader coordinator helper selection is not added here. Do not block the main demo pairing if you want to keep demonstrating its bookings, because the backend provides no unblock command.

## Repeat checks without resetting the demo

```powershell
# app/
.\preview.ps1 -Mode check
.\preview.ps1 -Mode build

# repository root; read-only
node app/tool/verify_coordination.mjs
node app/tool/verify_wallet.mjs --expect-20-coin-demo
```

The coordination verifier expects the main family's sharing and booking consents to be on. Restore them after a withdrawal test. Backend integration suites reset disposable fixtures; do not run them against the preserved user walkthrough. Live Gemini inference, actual BM/EN microphone/device playback, production deployment, automatic scheduling and push delivery remain outside these results.

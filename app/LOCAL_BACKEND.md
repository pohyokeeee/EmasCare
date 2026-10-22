# Flutter local backend and Stage 5 UI

The default app connects to the local `demo-emascare` Firebase emulators. Stage 5 UI is on `ui-stage5-wallet`, based on merged main `c178eb5`. It adds B's wallet and mock-redemption APIs and preserves check-ins, companion sessions and attendance. No cloud deployment is configured. See [STAGE5_VERIFICATION.md](STAGE5_VERIFICATION.md) for wallets, [STAGE4_VERIFICATION.md](STAGE4_VERIFICATION.md) for attendance and [STAGE3_VERIFICATION.md](STAGE3_VERIFICATION.md) for bookings/sessions.

## Start on this Windows computer

Use three PowerShell terminals. From the repository root in terminal 1:

If the backend and app are already running, open `http://127.0.0.1:8090` directly. Start only the services that have stopped. Installation is needed only on first setup or after the backend lockfile changes; stop this project's backend before reinstalling dependencies.

```powershell
cd 'C:\Users\user\Documents\PROJECTS\EmasCare'
# First installation only (or after package-lock.json changes):
npm.cmd ci
# Task-local settings; these do not change Windows configuration.
$env:JAVA_HOME='C:\Users\user\.jdks\openjdk-25.0.1'
$env:FUNCTIONS_DISCOVERY_TIMEOUT='60'
$env:FIREBASE_EMULATORS_PATH=Join-Path (Get-Location).Path '.cache/firebase/emulators'
npm.cmd run emulators
```

`EBADENGINE` warnings under system Node 24 refer to the Functions target of Node 22. This project installs its own pinned Node 22 for backend npm scripts. An `EPERM` error replacing `node_modules/re2/.../re2.node` can occur when a running Firebase process holds the file open: stop the project's emulator suite, then retry `npm.cmd ci`.

Wait for function definitions to load, including `getBackendContext`, `saveElderSettings`, `submitCheckIn`, `recordPhoneResponse`, `setHelperAvailability`, `createRequest`, `assignRequest` and `transitionRequest`. The current backend also includes Stage 4 attendance functions. The generic “all emulators ready” banner alone does not establish Functions readiness. This machine needed the 60-second discovery allowance on its first launch.

The workspace cache contains the official Firestore 1.22.0 runtime, verified against Firebase CLI's SHA-256 manifest. If the cache is absent, the CLI downloads it. On another computer, use your installed JDK 21+ path instead. Node/npm and the Flutter SDK must already be installed.

Terminal 2, repository root:

```powershell
npm.cmd run demo:reset
```

Reset is for disposable emulator fixtures. It restores both elders' settings/statuses and the six demo accounts, clears their known receipts/session-derived history and seeds `request_demo_ready` for an immediate phone-help walkthrough. Emulator data is in memory; restart and reset again for a fresh rehearsal.

Terminal 3:

```powershell
cd 'C:\Users\user\Documents\PROJECTS\EmasCare\app'
.\preview.ps1
```

Open **http://127.0.0.1:8090**. This is now the default preview port; 8080 belongs to Firestore. `preview.ps1 -Mode serve` serves an existing build; rebuild first after source changes. `-Mode dev` starts Flutter's development server. The script uses the installed Dart/Flutter snapshot because this machine's `flutter.bat` launcher stalls.

If the build succeeds but serving reports `EADDRINUSE` on 8090, another process already occupies that port. If it is this project's existing preview server, open the address and press Ctrl+Shift+R to load the new build; a second server is unnecessary. If another application owns the port, stop that application deliberately or use `preview.ps1 -Port 8091` and open port 8091 instead.

The first browser launch requires internet access for the pinned Firebase JS SDK. CanvasKit, fonts and artwork are bundled. Use a loopback browser on the same machine as the emulators. A physical phone or hosted/cloud origin needs a separate configuration.

## Accounts and browser sessions

All six emulator accounts use **`EmasCare-local-2026!`**:

| Scenario | Email |
| --- | --- |
| Elder | `elder@emascare.test` |
| Family | `family@emascare.test` |
| Helper | `helper@emascare.test` |
| Coordinator | `coordinator@emascare.test` |
| Standalone elder | `solo@emascare.test` |
| Unrelated family | `unrelated@emascare.test` |

Auth uses tab-scoped session persistence: refresh keeps the session, and separate newly opened tabs can use different accounts. If a browser duplicates a tab and copies its session, sign out in the duplicate before selecting the other account. No application code stores passwords. Roles, township and household come from the authenticated user's server profile, checked against `getBackendContext`; URL roles and preview controls cannot authorize live operations.

The release entry point configures the Auth emulator immediately after JS Auth initialization, before FlutterFire restores a saved user. This is necessary because the pinned FlutterFire Auth web plugin reapplies its stored emulator origin automatically only in debug mode. `web/firebase_local.mjs` uses the same SDK version and initialization dependencies as the pinned plugin; review it when upgrading FlutterFire. The Dart adapter connects all three emulators again before subscriptions or callables.

The Auth SDK's fixed warning banner is disabled in this loopback-only bootstrap because it covered phone navigation and dialog controls. The sign-in screen, toolbar and footer still label the local demo. This changes presentation only; emulator connection and origin guards are retained.

## Manual acceptance walkthrough

1. Sign in as elder in one tab and family in a separate tab. Press **Saya OK** in the elder tab. Both should show **Saya OK received** with the same MYT submission time. Repeated responses preserve the first response.
2. In elder settings, turn off **Share daily status with family** and save. Leave booking enabled. The family tab must immediately remove the rendered status and show **Daily status is private** while **Booking consent: on** remains visible. Refresh the family tab: it must still have no status. Backend rules additionally deny new/active daily-status reads after withdrawal.
3. Restore sharing and turn booking off, then save. Family status should return while **Booking consent: off** remains visible. My companion must hide requests and disable family creation until booking is restored.
4. Refresh elder. The signed-in account, settings and today's response must persist from the server. Sign out: private views clear immediately. Re-entering a different role in the hash URL must not change the server-owned role.
5. For an unsubmitted pause scenario, use the standalone elder **before** recording its phone response. Enable **Pause today**, change due time/grace if desired, and save. Saya OK is disabled and the saved pause survives refresh. Unpause and save before submitting. A pause on an already successful record retains its first OK response, as specified by the backend.
6. Sign in as coordinator. Only today's same-township `reminded`/`missed` records appear. The fresh standalone fixture is overdue. Click **Record phone response**, confirm that you actually spoke to the elder in this synthetic demo, and confirm the report. The row disappears; the standalone elder sees the stored OK response. This never initiates a phone call.
7. Sign in as unrelated family. It must show no linked elder/status/requests and must not query the demo elder's records. Sign in as helper to edit saved availability and follow assigned sessions; use the [Stage 3 walkthrough](STAGE3_VERIFICATION.md).
8. Test BM/EN, Preferences → Larger text / Gentler motion / Solid navigation, phone widths and desktop. Account → **Open design preview** signs out and opens clearly labelled fixtures; **Back to sign in** returns to the connected entry.

For a fresh repeat, stop test interactions and run `demo:reset` again. Do not reset while demonstrating a saved response.

## Verification commands

```powershell
# From app/
.\preview.ps1 -Mode check
.\preview.ps1 -Mode build
```

These cover Flutter analysis, Flutter tests, five existing browser-device bridge tests and two Firebase startup-order tests. The focused Dart tests exercise timestamps/envelopes, strict roles, stale auth callbacks, duplicate taps, retry identity/payload, consent withdrawal/cancellation, permission denial, unlinked accounts, empty queries and BM/large text layouts at 320/390/768/1440 pixels. They use a fake repository; the browser walkthrough and backend rules tests provide emulator evidence.

For backend checks while development emulators are already running, use `npm.cmd run test:integration` from the repository root. These reset/change disposable fixtures; close active demonstrations first. `npm.cmd test` starts its own suite, so stop the development emulators before running it. See `docs/BACKEND_CHECKINS.md` for backend ownership and detailed rules.

## Current limits

Authentication, elder settings/check-ins, family consent-gated daily status, coordinator phone reporting, companion requests/assignment, helper availability, sessions, attendance and own-wallet/mock redemption are connected. Township activities/places and permitted pairings are read-only. Participant pairing queries require both the participant ID and township constraints. All domain writes use the supplied Stage 2–5 callables, with version 1 envelopes and action-specific retry keys. Stream snapshots remain authoritative, so replayed responses cannot overwrite newer state.

Account → design preview retains a labelled in-memory journey. Connected mode uses real persisted requests, sessions, attendance and wallets. Elders submit ended in-person attendance from Activities → Past activities; coordinators verify/reject in Requests → Attendance review; elders and sharing-consented family read Attendance history. Booking consent does not grant attendance access, and neither family consent grants financial access. My rewards reads only the actual elder/helper's own wallet, reward outcomes, coin history and saved demo codes. Redemption uses the backend's 100-coin demo voucher; the default unconfigured policy leaves pending claims and zero balances, so live redemption reports insufficient funds. No earning rates or positive balances are invented. Voice/model, automatic reminders/notifications and scheduler features remain outside this integration. Tanya Dulu remains future work. Backend Functions, rules, indexes and scripts were not modified.

Run `node app/tool/verify_wallet.mjs` from the root for read-only wallet/privacy checks. After verifying the main elder's activity in the default demo, add `--expect-default-demo` to confirm a pending claim, zero balances and no financial transactions/redemptions. Do not use this default-state assertion against an intentionally configured earning-policy test.

Run `node app/tool/verify_attendance.mjs` from the repository root for read-only checks of the exact attendance queries. After the documented elder-verification/solo-rejection browser walkthrough, add `--expect-browser-results` to validate those saved reviews, privacy boundaries and unchanged zero coin balances. The verifier does not reset or mutate data.

Run `node app/tool/verify_community.mjs` from the repository root for read-only catalogue/companion permission checks against the running emulators. It signs into the six demo accounts without resetting or changing domain data.

Retry keys are retained in memory for the confirmed action until it succeeds or the user cancels it. They are cleared on sign-out/profile changes; reloading recovers persisted domain state rather than an unfinished retry. New actions get new keys. Malaysian date rollover refreshes date-scoped subscriptions; commands still select dates/timestamps on the server.

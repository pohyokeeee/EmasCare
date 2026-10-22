# EmasCare — Flutter Web

A responsive Flutter Web app owned by Developer A, connected to Developer B's local Stage 2–5 Firebase APIs. **Read [LOCAL_BACKEND.md](LOCAL_BACKEND.md) first** for exact emulator startup, accounts, connected features and manual verification. [STAGE5_VERIFICATION.md](STAGE5_VERIFICATION.md) covers wallets/rewards/mock redemption; [STAGE4_VERIFICATION.md](STAGE4_VERIFICATION.md) covers attendance; [STAGE3_VERIFICATION.md](STAGE3_VERIFICATION.md) covers bookings and sessions. The default app requires the emulators. Account → design preview retains separate sample screens.

## Run on this Windows computer

From PowerShell:

```powershell
cd "C:\Users\user\Documents\PROJECTS\EmasCare\app"
.\preview.ps1
```

Start/reset the backend as described in [LOCAL_BACKEND.md](LOCAL_BACKEND.md), then open **http://127.0.0.1:8090** after the app server prints its address. Keep the terminal open. Press Ctrl+C to stop it. Firestore uses 8080.

The script builds the app and serves it on the loopback address. It finds Flutter via `FLUTTER_ROOT`, your PATH, or this computer's existing `Documents/VS CODE/flutter` folder. To use another SDK, pass `-FlutterRoot 'C:\path\to\flutter'`. Flutter must already be initialized, and Node.js must be installed. Verified with Flutter 3.38.5 / Dart 3.10.4.

Useful modes:

```powershell
.\preview.ps1 -Mode serve   # Use an existing build; no compile
.\preview.ps1 -Mode dev     # Flutter development server; follow terminal reload instructions
.\preview.ps1 -Mode check   # Analyzer, Flutter tests and browser-bridge tests
```

The helper uses Flutter's installed Dart/snapshot entry point because this machine's `flutter.bat` launcher stalls. On a machine with a working Flutter launcher, the standard commands also work:

```powershell
flutter pub get
flutter run -d chrome --web-port 8090
```

## Try the explicit design preview

Use **Explore the design preview** from sign-in, or Account → **Open design preview** while connected (signs out first). The following interactions use fixtures only:

1. Press **Saya OK**. The sample check-in updates locally. Open the role menu near the top right and select **Family** to see the same sample status.
2. Select **Helper** and toggle availability. It changes only the sample repository.
3. Open **Activities**, filter Movement/Community, open an activity, read its access notes, and navigate to the companion preview.
4. Open **My rewards** for elder/helper. The wallet deliberately shows no balance; the illustrative voucher costs 100 coins but redemption is disabled.
5. Select **Coordinator** and explore Overview, Requests, Places and People. These show read-only fixtures.
6. Use **BM / EN**, Preferences → Larger text, Gentler motion or Solid navigation. Reset sample state in Preferences. Reloading clears all local state.
7. In Preferences, use the Teman voice device check. Recording starts only on **Record 5 seconds**, asks for microphone permission, stops tracks after capture, and keeps the clip in memory for local playback. Spoken read-back requires an installed voice for the selected language. No audio is uploaded or parsed by AI.

Hash routes such as `/#/family/today`, `/#/helper/rewards` and `/#/coordinator/activities` support direct entry and browser history. Role switching is a preview control, not authentication or authorization.

## What Phase 1 delivers

- Responsive desktop sidebar and phone bottom navigation; four distinct role homes.
- Shared cards, buttons, badges, people rows, detail sheets and code-native park illustrations.
- Warm white / forest green styling, clear type hierarchy and explicit 400–700 Manrope font weights.
- Immediate press feedback with interruptible critically damped springs; reduced-motion support; translucent navigation with solid / increased-contrast fallbacks.
- Larger text and BM/English core interface copy. Fixture names, places and some coordinator request descriptions remain sample content.
- Flutter semantics enabled on web, keyboard-focusable controls, explicit preview labels.
- UI view models and a replaceable `EmasRepository` interface backed by `MockEmasRepository`.
- A browser recording/read-back feasibility tool with denied-permission and unsupported-device messages.

## Connected features and remaining scope

Connected mode has sign-in/out, saved independent consent, due/grace/pause settings, real local-emulator check-ins, family status and coordinator phone reporting. Phase 2 also reads township activities/places, permitted pairings and the helper's own saved availability. Place details show recorded accessibility, expiring notices and approved HTTPS Google Maps links; seeded access information is illustrative.

Phase 3 connects helper availability/weekly hours, elder/consented-family requests, coordinator assignment, accept/start/finish/cancel and each participant's confirmation. Live request streams survive refresh through server state. Activity bookings use exact recorded schedules and places; standalone phone help sends explicit null activity/place IDs. Form notes remain preview-only because Stage 3 does not accept them.

Phase 4 adds Past activities and Attendance history under Activities. Actual elders submit ended in-person attendance; coordinators review submitted records from Requests → Attendance review, using a trusted evidence method and a factual note. Family history follows sharing consent, independently of booking. Existing companion attendance is reused without another participation. The local SDK warning no longer covers phone navigation; in-app local-demo labels remain.

Stage 5 connects the existing My rewards destination to the actual elder/helper's own wallet, participation outcomes, immutable coin history, mock voucher catalogue and saved DEMO codes. A confirmed purchase uses the protected redemption callable and preserves its key across retries. Missing/denied data is not shown as zero, and old receipt balances cannot overwrite current streams. Family/coordinators have no proxy spending interface.

Notifications/automatic reminders, family cheers and AI voice parsing remain pending. In design-preview mode, the request → assignment → helper session → two-participant confirmation journey uses separate in-memory samples that disappear on reload. Connected attendance and wallet history contain server records only. After seed/reset, run `npm.cmd run demo:configure-rewards` from the repository root to apply the approved 20-coin rule and reconcile earlier verified pending records. Wallets start at zero and are funded through verified participation, not positive-balance seeds. The SDP entry remains a mock module entry.

The owner's 22 Oct reward decision is **20 coins per verified activity/helping session for both elders and helpers**. All five supported action types and earlier verified pending participations are included, once per canonical participation. Five credits fund the 100-coin demo voucher. The Stage 5 response shapes are documented in B's handover. This app does not implement the superseded monthly award or fabricate wallet balances. Tanya Dulu is future work and has no screen here.

Browser API availability is not proof of successful microphone capture or audible speech on the presentation device. Try the device check there; keep the manual activity UI available if audio fails.

## Source map and handoff

| Location | Purpose |
| --- | --- |
| `lib/app/` | App/router, shared preview state and responsive shell |
| `lib/shared/` | Theme, reusable components, spring feedback and illustrations |
| `lib/models/` | Separate fixture UI models and documented Stage 2–5 backend records |
| `lib/data/emas_repository.dart` | Repository interface and local mock |
| `lib/data/community_repository.dart`, `lib/models/community_models.dart` | Scoped read-only catalogue, place, pairing and helper records |
| `lib/data/session_repository.dart`, `lib/models/session_models.dart`, `lib/app/session_workflow_controller.dart` | Stage 3 typed callables, scoped request streams, frozen retries and cleanup |
| `lib/data/attendance_repository.dart`, `lib/models/attendance_models.dart`, `lib/app/attendance_controller.dart`, `lib/features/community/attendance_views.dart` | Stage 4 attendance submission, scoped history, coordinator review and retry/consent cleanup |
| `lib/data/wallet_repository.dart`, `lib/models/wallet_models.dart`, `lib/app/wallet_controller.dart`, `lib/features/wallet/wallet_view.dart` | Stage 5 owner-scoped wallet, reward outcomes, ledger, demo vouchers and guarded redemption |
| `lib/features/community/` | Phase 2 catalogue, access details, request/review and companion/session UI |
| `lib/app/companion_demo_controller.dart`, `lib/models/companion_ui_models.dart` | Explicitly local sample workflow; no Stage 3 wire contract |
| `lib/features/role_views.dart` | Four role previews and activity/companion/reward views |
| `lib/platform/`, `web/preview_bridge.js` | Conditional web bridge and local audio/device check |
| `test/preview_test.dart` | Interactions, role navigation and responsive larger-text checks |
| `tool/browser_bridge.test.cjs` | Audio permission, track cleanup, playback and speech fallbacks |

Connected code lives in `lib/data/firebase_backend_repository.dart`, `lib/models/backend_models.dart`, `lib/app/session_controller.dart` and `lib/features/connected/`. It uses B's Stage 2 guide/fixtures. `EmasCareApp(backend: ...)` injects the live adapter; `EmasCareApp(repository: ...)` remains available for fixture-only tests. Live roles are server-owned and cannot be switched with the preview selector. Reward policy and permission checks remain in the backend.

## Verification

See [the Stage 2 verification record](STAGE2_VERIFICATION.md) for connected-mode tests, real emulator/browser results and remaining limits. [LOCAL_BACKEND.md](LOCAL_BACKEND.md) contains the full restart and manual walkthrough.

See [the Phase 2 handover](PHASE2_HANDOVER.md) for the 41-test check run, read-only checks against all six emulator accounts, browser walkthrough and screenshots.

See [Stage 3 verification](STAGE3_VERIFICATION.md) for the current connected companion journey and acceptance evidence.

See [Stage 4 verification](STAGE4_VERIFICATION.md) for attendance scenarios, current test results and the read-only attendance verifier.

See [Stage 5 verification](STAGE5_VERIFICATION.md) for connected wallet/redemption scenarios, current test results, screenshots and the read-only financial query verifier.

See the [Phase 5 completion audit](PHASE5_VERIFICATION.md) for the additional voucher translation, receipt validation and purchase-feedback/retry regressions on `ui-phase-5`, the approved 20-coin configuration and the earned-coins demo verification.

See [the Phase 1 verification record](PHASE1_VERIFICATION.md) for observed browser results, screenshots and device-audio limits.

```powershell
flutter analyze
flutter test
node --test tool/browser_bridge.test.cjs
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run --pwa-strategy=none
node --test tool/firebase_bootstrap.test.cjs
node tool/serve.cjs 8090
```

The Flutter tests exercise 320, 390, 768 and 1440-pixel layouts across every role and navigation section with BM and larger text, plus check-in/family sharing in the local mock, availability, activity filtering/details, preferences and wallet boundaries. These tests do not establish live backend or device-audio acceptance.

The release bundles CanvasKit, fonts and artwork locally. A fresh reload is needed after rebuilding. No service-worker caching is generated for this preview.

Manrope is distributed under the SIL Open Font License; see `assets/fonts/OFL.txt`. The variable source comes from the official [Google Fonts Manrope directory](https://github.com/google/fonts/tree/main/ofl/manrope). `tool/prepare_fonts.py` generated the bundled static font assets using FontTools 4.67.0; Python/FontTools are not required to run or build the app.

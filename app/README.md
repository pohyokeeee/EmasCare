# EmasCare — Phase 1

A responsive Flutter Web interface preview for Developer A. All four Flutter role views, including coordinator, belong to A; Developer B supplies the backend. This follows the ownership override in the supplied contract.

## Run on this Windows computer

From PowerShell:

```powershell
cd "C:\Users\user\Documents\PROJECTS\EmasCare\app"
.\preview.ps1
```

Open **http://127.0.0.1:8080** after the server prints its address. Keep the terminal open. Press Ctrl+C to stop it.

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
flutter run -d chrome --web-port 8080
```

## Try it

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

## Still pending

This is an interface foundation, not the full two-day MVP. There is no sign-in, Firebase connection, saved consent, real check-in/reminder/escalation, booking, session transition, reward credit, redemption, live Maps/warnings, coordinator mutation, family cheer write, or AI voice parsing. Sample status changes disappear on reload. Progress rings, pairings, dates, requests and participant names are synthetic. The SDP entry is a mock module entry.

The reward decision remains **coins for elders and helpers after each eligible verified completion**. Rates, detailed eligibility and exact response JSON still require agreement. This app does not implement the superseded monthly award or fabricate wallet balances. Tanya Dulu is future work and has no screen here.

Browser API availability is not proof of successful microphone capture or audible speech on the presentation device. Try the device check there; keep the manual activity UI available if audio fails.

## Source map and handoff

| Location | Purpose |
| --- | --- |
| `lib/app/` | App/router, shared preview state and responsive shell |
| `lib/shared/` | Theme, reusable components, spring feedback and illustrations |
| `lib/models/` | UI view models; no approved wire serialization |
| `lib/data/emas_repository.dart` | Repository interface and local mock |
| `lib/features/role_views.dart` | Four role previews and activity/companion/reward views |
| `lib/platform/`, `web/preview_bridge.js` | Conditional web bridge and local audio/device check |
| `test/preview_test.dart` | Interactions, role navigation and responsive larger-text checks |
| `tool/browser_bridge.test.cjs` | Audio permission, track cleanup, playback and speech fallbacks |

Replace the mock through `EmasCareApp(repository: ...)` after agreeing response shapes with B. Real auth must select a server-owned role; the preview role selector must not authorize backend actions. Keep reward amounts, permission checks and session completion in the backend. Preview methods are deliberately named `preview*` and do not establish callable signatures.

## Verification

See [the Phase 1 verification record](PHASE1_VERIFICATION.md) for observed browser results, screenshots and device-audio limits.

```powershell
flutter analyze
flutter test
node --test tool/browser_bridge.test.cjs
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run --pwa-strategy=none
node tool/serve.cjs 8080
```

The Flutter tests exercise 320, 390, 768 and 1440-pixel layouts across every role and navigation section with BM and larger text, plus check-in/family sharing in the local mock, availability, activity filtering/details, preferences and wallet boundaries. These tests do not establish live backend or device-audio acceptance.

The release bundles CanvasKit, fonts and artwork locally. A fresh reload is needed after rebuilding. No service-worker caching is generated for this preview.

Manrope is distributed under the SIL Open Font License; see `assets/fonts/OFL.txt`. The variable source comes from the official [Google Fonts Manrope directory](https://github.com/google/fonts/tree/main/ofl/manrope). `tool/prepare_fonts.py` generated the bundled static font assets using FontTools 4.67.0; Python/FontTools are not required to run or build the app.

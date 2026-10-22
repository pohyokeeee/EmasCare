# EmasCare

For the final MVP, follow the [single-command startup and connected walkthrough](app/FINAL_DEMO_GUIDE.md). From the repository root, run `.\app\demo.ps1`. It preserves demo history and can back up/restart saved emulator data; the manual reset workflow below is only for deliberately disposable fixtures.


The Flutter Web app in [`app/`](app/README.md) now connects to the local Firebase backend for sign-in, elder check-ins/settings, consent-gated family status and coordinator phone responses. It preserves responsive navigation, BM/EN and accessibility controls, with the original sample screens available in an explicit design-preview mode.

Phase 3 connects companion booking, helper availability, coordinator assignment and the session lifecycle to B's Stage 3 emulator APIs. Elders and helpers confirm separately, and family request visibility follows current booking consent. The labelled design preview remains available. See [Stage 3 verification and review steps](app/STAGE3_VERIFICATION.md); [Phase 2 handover](app/PHASE2_HANDOVER.md) records the earlier sample-only delivery.

On Windows, start and seed the backend first, then run `app/preview.ps1` and open `http://127.0.0.1:8090`. Flutter, Node.js and a JDK are required. Follow the [exact local startup and manual verification steps](app/LOCAL_BACKEND.md).

Phase 4 adds elder submission for ended in-person activities, coordinator attendance verification/rejection and saved elder/family history. Family attendance follows sharing consent independently of booking. See [Phase 4 verification and walkthrough](app/STAGE4_VERIFICATION.md).

Stage 5 connects My rewards to the elder/helper's saved wallet, reward outcomes, coin history, mock voucher catalogue and demo redemption. The owner-approved reward is **20 coins per verified activity or helping session for both roles**. After seeding the local emulators, run `npm.cmd run demo:configure-rewards` to apply it and settle earlier verified pending records. Five distinct credits fund the 100-coin demo voucher. See [current Phase 5 verification](app/PHASE5_VERIFICATION.md).

The [Phase 5 completion audit](app/PHASE5_VERIFICATION.md) on `ui-phase-5` covers translation, receipt and purchase-feedback/retry fixes, the approved 20-coin configuration and earned-coins redemption verification.

Port 8090 is the app's default; Firestore uses 8080. Bare seed/reset leaves the foundation policy unconfigured until the approved configuration command is run. Stage 6 connects coordinator operations, reports, place warnings, consent-scoped in-app updates, family cheers and progress/availability summaries to Flutter. Voice/text booking uses the backend parser with manual booking available when the provider is disabled. Live Gemini/audio verification requires local provider configuration. See [Stage 6 verification and walkthrough](app/STAGE6_VERIFICATION.md). No cloud services have been deployed.

- [Current implementation plan: two people, two days, Flutter Web MVP demo](docs/PROTOTYPE_PLAN_2_DAYS.md)
- [Product and pilot plan](Township%20%28SimeDarby%29%20Hackathon%202026.md)
- [Original three-day implementation plan (reference)](docs/FULL_IMPLEMENTATION_PLAN_3_DAYS.md)
- [Backend Stage 1: local setup, demo accounts and teammate handover](docs/BACKEND_FOUNDATION.md)
- [Backend Stage 2: check-ins, consent and frontend handover](docs/BACKEND_CHECKINS.md)
- [Backend Stage 3: companion requests, sessions and frontend handover](docs/BACKEND_SESSIONS.md)
- [Backend Stage 4: standalone attendance, coordinator verification and frontend handover](docs/BACKEND_ATTENDANCE.md)
- [Backend Stage 5: configured rewards, wallets and mock redemption](docs/BACKEND_WALLET.md)
- [Backend Stage 6: coordinator APIs, notifications, progress, voice parsing and teammate fixtures](docs/BACKEND_COORDINATION.md)
- [Integration rehearsal: safe setup, real API walkthrough and frontend handoff](docs/INTEGRATION_REHEARSAL.md)

Scope decision (21 Oct 2026): Tanya Dulu is a future feature and is excluded from the current MVP and prototype builds.

Reward decision (22 Oct 2026): each verified community activity, walk, sitting session, carrying-help session or phone-help session awards **20 coins to each actual elder/helper participant**. Existing verified pending participation is included, once per canonical participation. This replaces earlier role-rate suggestions and the old monthly award. The separately shared contract v1, revision 2, defines the interface; outing classifications remain separate. Local foundation wallets start at zero and gain funds only through verified evidence.

Developer A owns all Flutter code, including the coordinator screen, shared Dart models and repository adapter. Developer B owns the backend. This overrides the older ownership table in the implementation plan.

The backend currently runs locally on Firebase Auth, Firestore and Functions emulators using `demo-emascare`. See the setup guide before starting. No cloud resources or hosted release have been provisioned.

# EmasCare

The Flutter Web app in [`app/`](app/README.md) now connects to the local Firebase backend for sign-in, elder check-ins/settings, consent-gated family status and coordinator phone responses. It preserves responsive navigation, BM/EN and accessibility controls, with the original sample screens available in an explicit design-preview mode.

Phase 3 connects companion booking, helper availability, coordinator assignment and the session lifecycle to B's Stage 3 emulator APIs. Elders and helpers confirm separately, and family request visibility follows current booking consent. The labelled design preview remains available. See [Stage 3 verification and review steps](app/STAGE3_VERIFICATION.md); [Phase 2 handover](app/PHASE2_HANDOVER.md) records the earlier sample-only delivery.

On Windows, start and seed the backend first, then run `app/preview.ps1` and open `http://127.0.0.1:8090`. Flutter, Node.js and a JDK are required. Follow the [exact local startup and manual verification steps](app/LOCAL_BACKEND.md).

Phase 4 adds elder submission for ended in-person activities, coordinator attendance verification/rejection and saved elder/family history. Family attendance follows sharing consent independently of booking. See [Phase 4 verification and walkthrough](app/STAGE4_VERIFICATION.md).

Stage 5 connects My rewards to the elder/helper's saved wallet, reward outcomes, coin history, mock voucher catalogue and demo redemption. The default policy is unconfigured: balances stay zero and verified participation remains pending rather than inventing earnings. See [Stage 5 verification and walkthrough](app/STAGE5_VERIFICATION.md).

Port 8090 is the app's default; Firestore uses 8080. Actual coin awards need approved earning rules; voice APIs remain pending. No cloud services have been deployed.

- [Current implementation plan: two people, two days, Flutter Web MVP demo](docs/PROTOTYPE_PLAN_2_DAYS.md)
- [Product and pilot plan](Township%20%28SimeDarby%29%20Hackathon%202026.md)
- [Original three-day implementation plan (reference)](docs/FULL_IMPLEMENTATION_PLAN_3_DAYS.md)
- [Backend Stage 1: local setup, demo accounts and teammate handover](docs/BACKEND_FOUNDATION.md)
- [Backend Stage 2: check-ins, consent and frontend handover](docs/BACKEND_CHECKINS.md)
- [Backend Stage 3: companion requests, sessions and frontend handover](docs/BACKEND_SESSIONS.md)
- [Backend Stage 4: standalone attendance, coordinator verification and frontend handover](docs/BACKEND_ATTENDANCE.md)
- [Backend Stage 5: configured rewards, wallets, mock redemption and remaining policy decisions](docs/BACKEND_WALLET.md)

Scope decision (21 Oct 2026): Tanya Dulu is a future feature and is excluded from the current MVP and prototype builds.

Reward decision (21 Oct 2026): elders and helpers earn coins after each eligible completed activity or helping session. This replaces the fixed monthly award. The separately shared contract v1, revision 2, defines the agreed interface; reward amounts, detailed eligibility and ambiguous outing definitions remain pending. Local foundation wallets start at zero.

Developer A owns all Flutter code, including the coordinator screen, shared Dart models and repository adapter. Developer B owns the backend. This overrides the older ownership table in the implementation plan.

The backend currently runs locally on Firebase Auth, Firestore and Functions emulators using `demo-emascare`. See the setup guide before starting. No cloud resources or hosted release have been provisioned.

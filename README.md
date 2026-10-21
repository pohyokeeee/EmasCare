# EmasCare

The Flutter Web app in [`app/`](app/README.md) now connects to the local Firebase backend for sign-in, elder check-ins/settings, consent-gated family status and coordinator phone responses. It preserves responsive navigation, BM/EN and accessibility controls, with the original sample screens available in an explicit design-preview mode.

Phase 2 adds a connected, read-only activity/access catalogue and permitted companion/availability summaries. A separate labelled sample journey covers requests, coordinator assignment, helper session steps and both participant confirmations while Developer B finishes Stage 3. See [Phase 2 handover and review steps](app/PHASE2_HANDOVER.md).

On Windows, start and seed the backend first, then run `app/preview.ps1` and open `http://127.0.0.1:8090`. Flutter, Node.js and a JDK are required. Follow the [exact local startup and manual verification steps](app/LOCAL_BACKEND.md).

Port 8090 is the app's default; Firestore uses 8080. Booking, sessions, rewards, redemption and voice APIs remain pending. No cloud services have been deployed.

- [Current implementation plan: two people, two days, Flutter Web MVP demo](docs/PROTOTYPE_PLAN_2_DAYS.md)
- [Product and pilot plan](Township%20%28SimeDarby%29%20Hackathon%202026.md)
- [Original three-day implementation plan (reference)](docs/FULL_IMPLEMENTATION_PLAN_3_DAYS.md)
- [Backend Stage 1: local setup, demo accounts and teammate handover](docs/BACKEND_FOUNDATION.md)
- [Backend Stage 2: check-ins, consent and frontend handover](docs/BACKEND_CHECKINS.md)
- [Backend Stage 3: companion requests, sessions and frontend handover](docs/BACKEND_SESSIONS.md)
- [Backend Stage 4: standalone attendance, coordinator verification and frontend handover](docs/BACKEND_ATTENDANCE.md)

Scope decision (21 Oct 2026): Tanya Dulu is a future feature and is excluded from the current MVP and prototype builds.

Reward decision (21 Oct 2026): elders and helpers earn coins after each eligible completed activity or helping session. This replaces the fixed monthly award. The separately shared contract v1, revision 2, defines the agreed interface; reward amounts, detailed eligibility and ambiguous outing definitions remain pending. Local foundation wallets start at zero.

Developer A owns all Flutter code, including the coordinator screen, shared Dart models and repository adapter. Developer B owns the backend. This overrides the older ownership table in the implementation plan.

The backend currently runs locally on Firebase Auth, Firestore and Functions emulators using `demo-emascare`. See the setup guide before starting. No cloud resources or hosted release have been provisioned.

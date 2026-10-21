# EmasCare

Phase 1 local Flutter Web preview is in [`app/`](app/README.md). It includes four role previews, responsive navigation, BM/EN core text and local sample interactions. It is not connected to Firebase yet.

On Windows, run `app/preview.ps1` from PowerShell, then open `http://127.0.0.1:8080`. Flutter and Node.js are required. See the app README for development commands and the exact preview boundaries.

When running the preview alongside the backend, use `app/preview.ps1 -Port 8090` and open `http://127.0.0.1:8090`; Firestore uses port 8080. The preview remains a local mock until Developer A connects the Firebase adapter.

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

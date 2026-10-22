# Integration rehearsal: backend ready, Flutter handoff next

Stage 6 backend PR #13 is merged. This work is on `backend-integration-rehearsal`, based on main `66c4854`. Developer B prepares and verifies backend integration. Developer A still owns all Flutter screens, shared models, navigation and repository adapters. No Flutter source is changed here.

## Run the backend

If the local emulators are not already running, start this from the repository root in **terminal 1** and keep it running:

```powershell
npm.cmd run emulators
```

When the emulators are ready, open **terminal 2** in the same repository:

```powershell
npm.cmd run demo:prepare
npm.cmd run demo:check
```

`demo:prepare` checks the exact local `demo-emascare` project, seeds an empty store, applies the owner-approved 20-coin configuration, reconciles verified pending participation and creates four extra **uncompleted assigned** session fixtures. Existing data is preserved: it does not rerun the old seed over existing settings, request history or wallets. Partial consent/profile data, a conflicting policy or orphan financial history requires operator review and produces an error. It never silently resets the demo.

`demo:check` signs in all six demo accounts and performs read-only callable/Firestore verification. It checks current profiles, own-wallet/ledger consistency, approved reward entries, family financial denial, protected progress, suppressed availability and coordinator permissions. Results are saved to ignored `.cache/integration-readiness.json`, with no tokens/passwords/audio. It does not mark Flutter or live Gemini testing complete.

Use the existing local-only accounts in [the foundation guide](BACKEND_FOUNDATION.md). The four main accounts are `elder@emascare.test`, `family@emascare.test`, `helper@emascare.test` and `coordinator@emascare.test`. Password: `EmasCare-local-2026!`. `solo@emascare.test` and `unrelated@emascare.test` are permission-test accounts. These are emulator credentials, not cloud accounts.

Developer A can start the existing Flutter preview separately using [the app startup guide](../app/LOCAL_BACKEND.md). Backend emulator addresses are Auth `127.0.0.1:9099`, Firestore `127.0.0.1:8080`, Functions `127.0.0.1:5001`, region `asia-southeast1`. The preview normally uses `http://127.0.0.1:8090`.

## Run the API walkthrough

With terminal 1 still running:

```powershell
npm.cmd run demo:rehearse
```

This command **changes the local demo through authenticated callable APIs**. It is not a browser test. It requires the main elder's existing sharing and booking consent to be enabled, and an unpaused check-in. It does not grant withdrawn consent or unpause the elder automatically.

For hands-on Flutter testing of uncompleted sessions, use `demo:prepare` and `demo:check` on a fresh demo and let the UI complete the sessions. Running `demo:rehearse` first completes those same fixtures; afterward they are useful for history, reward, voucher and notification inspection. Start a separate fresh rehearsal explicitly if you want to repeat those lifecycle actions through the UI.

| Walkthrough | Evidence |
| --- | --- |
| Saya OK and due processing | Persisted check-in, repeatable due action and retained warning-review semantics |
| Five companion/help sessions | Helper accept/start/finish, then separate helper and elder confirmations |
| Standalone activity | Elder submission and coordinator roster verification of the seeded ended demo activity |
| Rewards | 20 coins per actual verified participant; five helper credits, six elder credits on a clean store |
| Voucher purchase | Each actual owner redeems 100 earned coins; same-key retry gives the same persisted mock voucher |
| Consent and cheers | One clap for a verified outing; sharing withdrawal denies progress/read-receipt replay while booking access stays available; original settings restored in `finally` |
| Coordinator actions | Report review to done, explicit place warning and a separate solo-elder helper block |
| Privacy/readiness | Own financial streams, family denial, sanitized progress and small-cohort suppression |

On a clean prepared store the elder ends with **20 coins**, the helper with **0**, and both own one saved 100-coin demo voucher. These balances come from the existing completion reward engine. No positive wallet opening balance, reward entry, completed session or attendance verification is seeded.

The extra assigned fixtures are `request_rehearsal_1` (walk), `_2` (sit), `_3` (carry), `_4` (phone), alongside the existing `request_demo_ready` (phone). They have distinct underlying help-session identities and non-overlapping past synthetic schedules. Their final completion time is the real server time of confirmation. Walk and standalone activity count as two outings; phone does not count, and standalone sit/carry remains pending definition independently of earning eligibility.

This assignment fixture setup does not prove coordinator assignment via Flutter; include that actual create/assign path in the joint UI walkthrough. The saved solo-elder block does not disable the main elder/helper pairing. The hall warning remains visible for coordinator review. After the API walkthrough, histories, receipts and notices remain available for UI inspection.

Re-running preparation preserves existing completion/consent/financial records. Re-running the walkthrough uses the same participation and purchase identities, so it cannot create extra credits or vouchers. A cancelled or blocked fixture is preserved and requires operator review. A genuine later purchase in the app uses its own new action key and sufficient earned funds. Settings, report and warning operations are visible demo actions, not hidden background changes.

Results are saved to ignored `.cache/integration-rehearsal.json`. It contains successful step names and safe demo results, with explicit pending UI/audio verification. A command that fails exits unsuccessfully; only trust an overall passed report with a current timestamp. Review the terminal error and rerun after fixing it. Do not treat an older result file as proof for a new failed attempt.

If you intentionally want to erase the known demo actors' existing records for a fresh rehearsal, use `npm.cmd run demo:reset`, then `npm.cmd run demo:prepare`. The reset is separate and explicit. Stopping the emulators normally discards their in-memory data; these commands do not add import/export persistence.

## Joint Flutter checklist

Send Developer A [the Stage 6 guide](BACKEND_COORDINATION.md), [exact fixtures](fixtures/stage6_coordination.json) and [the copyable integration prompt](FRONTEND_STAGE6_HANDOFF.md). She should connect and test:

- [ ] Report submission, coordinator new/seen/done review and role/error feedback.
- [ ] Coordinator warning set/clear; expired warning remains marked for review.
- [ ] Actual elder/coordinator blocking; family denial; blocked helper cannot be assigned or accept/start.
- [ ] Operator due processing, notification lists/read actions, and current recipient permissions.
- [ ] Sharing withdrawal hides old sharing notices/progress/cheers; booking consent stays separate.
- [ ] Activity/session completion and owner-visible 20-coin claims/ledger; retries preserve balances.
- [ ] Standalone attendance, family clap and progress refresh; phone excluded and sit/carry pending classification.
- [ ] Availability demo/suppression labels; no individual schedules or reconstructing totals.
- [ ] Existing create -> coordinator assign -> helper lifecycle -> separate participant confirmations through Flutter.
- [ ] BM/EN, narrow screen, large text, failures and stable mutation-key retries.
- [ ] Voice draft review, missing-field clarification, manual booking fallback and no booking before confirmation.

Live Gemini/BM-EN microphone verification is **pending** until a supported model and server-side key are configured. The rehearsal never calls a live provider. Use [the voice setup section](BACKEND_COORDINATION.md#voice-parser-and-live-configuration); do not paste credentials in chat, Flutter or Git. UI/browser verification is pending until Developer A runs and records it. No cloud deployment is included.

## Backend verification

With no emulators already running, `npm.cmd run test:journey` starts/stops local emulators and runs the fresh-store, preserved-state, real-callable walkthrough, repeated-run and corruption-guard checks. It resets only known demo actors in its isolated test run. Keep these automated tests separate from the manually preserved rehearsal store.

Verified locally on 22 October 2026: TypeScript build, all 24 unit checks and all 8 integration-rehearsal tests passed. The actual `demo:prepare`, `demo:check` and `demo:rehearse` commands also passed, producing 12 journey steps plus 14 read-only readiness checks. The saved prepared store has elder balance 20, helper balance 0, and one earned demo voucher for each. Repeating the tested journey added no credits or purchases. These results do not claim connected Flutter or live audio verification.

After changes are reviewed: commit, push and open a PR for this integration tooling. Share the handoff with Developer A, record the joint UI outcomes, resolve actual integration defects and perform a final demo rehearsal before deployment work.

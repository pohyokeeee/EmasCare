# Phase 5 completion audit

Branch: `ui-phase-5`, based on merged main `874afa3`. This branch reuses the connected My rewards implementation merged in PR #11, fixes additional errors, and applies the owner's 22 Oct decision: **20 coins per verified activity/helping session for elders and helpers alike**. No cloud deployment is included. Backend Functions, rules, indexes and the existing reward/reconciliation engine are unchanged. A guarded local configuration command, approved configuration and configuration tests were added.

## Implemented fixes

- Voucher cards fall back between BM and EN when one title is unavailable. A record with no usable title fails during parsing and produces the existing recoverable data error rather than a rendering exception. Parsed titles cannot be mutated afterward.
- A redemption receipt must match the voucher in the confirmed immutable purchase. An unexpected response cannot announce that purchase as successful or overwrite the current wallet stream.
- A new confirmation sheet does not show a previous purchase's success message. The saved result remains available on the wallet screen and in the user's server-owned voucher history.
- Deactivating/removing a catalogue voucher preserves the existing purchase's retry control in its open sheet. A retry retains the original key and voucher; the backend decides whether an original receipt or a failure applies. No new purchase can start from the unavailable card.
- Reward cards show the verified date, outcome and actual coin amount. Internal policy version identifiers stay in the saved records without cluttering the participant interface.

The existing Apple-inspired green/warm-white surfaces, Manrope typography, immediate critically damped press feedback, accessible confirmation sheets, BM/EN, larger text, reduced motion and solid navigation remain. These changes improve the existing approved design without adding another navigation destination.

## Approved earning rules

All five existing canonical actions (`activity_attendance`, `walk_with_me`, `sit_with_me`, `carry_light_item`, `phone_help`) award 20 coins to each actual elder/helper beneficiary after verification. The latest fixed-rate instruction supersedes the earlier helper/elder rate difference. "All activities" includes earlier verified pending participations; their original verification timestamps are retained. Daily check-ins are outside the existing activity/session reward engine. One canonical participation earns once, including accompanied activities represented by both session and attendance evidence.

The reviewed configuration is `../docs/fixtures/reward_policy_20_coins.json`, version `owner-20-all-v1`. Its epoch applicability start includes earlier verified records. The generic draft template remains inactive. `npm.cmd run demo:configure-rewards` converts dates to Firestore Timestamp, applies this exact immutable version to the guarded `demo-emascare` loopback emulators, then runs the existing evidence-checking reconciliation. It never writes a balance directly and refuses a different active policy or conflicting approved version.

Bare seed/reset intentionally clears the active policy pointer. Reapply configuration afterward. No positive opening balances or completed history are seeded.

## Verification

Four regression cases reproduced the translation crash, wrong-voucher success, stale success message and disappearing retry before the fixes. They were added to the existing Stage 5 fixture/controller/widget tests. The test driver now disposes controllers inside the widget test before the binding checks pending timers.

Current verification:

- Flutter analyzer: clean on the final source.
- Read-only six-account wallet verifier with `--expect-20-coin-demo`: **62 checks passed**, including owner/township queries, family/other-participant denial, private policy records, exact 20-coin credits, earned redemptions and ledger consistency. The earlier bare-default run also passed 52 checks before policy activation.
- Full Flutter suite: **88 tests passed**, including all sixteen Stage 5 tests and the four new regression cases.
- All sixteen Stage 5 tests are included. At 320/390/768/1440 widths with BM, larger text, reduced motion and solid navigation, failed confirmation and voucher deactivation preserve a reachable retry; it reuses the original key without changing the balance.
- Browser/device and startup tests: **7 passed**. Final release web build succeeded (90.3 seconds).
- Backend TypeScript build passed. **17 unit tests passed**, including all ten role/action combinations at exactly 20 coins, historical applicability, local-only guards, refusal of custom CLI amounts, active-policy conflict and approved-version immutability.
- Live emulator earning rehearsal: existing pending attendance credited 20; phone/walk/sit/carry sessions credited 20 to both participants only after separate confirmations. A newly booked and coordinator-assigned accompanied activity ran through its actual start/end times and both confirmations, crediting 20 to each role. Repeated confirmations and duplicate attendance did not add credits. Both accounts redeemed an earned 100-coin voucher through Flutter. Reapplying configuration and reconciling all 11 participations changed no balances.
- Final rebuilt browser preview: both roles restored automatically on a subsequent stable refresh, with the correct own balances, 20-coin claims, debit history and saved DEMO codes. BM renders the actual credited amounts and voucher. Internal policy IDs no longer appear on reward cards. Elder/helper browser error logs were empty. The initial reload during backend warm-up showed the existing recoverable profile connection message; Retry profile restored it, and both subsequent refresh checks passed.
- Existing backend evidence records 84 integration/rules tests passing on the unchanged Functions/rules, including accounting/races and isolated configured-policy cases. That is prior regression evidence; the new owner-approved earning rehearsal and 62 financial/privacy checks were run on this branch without resetting the saved demo.

Saved rehearsal state: the elder has six 20-coin credits (120 earned), one 100-coin demo redemption and 20 remaining. The helper has five 20-coin credits (100 earned), one demo redemption and zero remaining. Their immutable ledger sums match the saved wallets. The extra elder credit is the earlier standalone activity. These are synthetic demo participants and sessions verified through the existing callables, with no fabricated opening funds or merchant fulfilment.

## Files

| File | Purpose |
| --- | --- |
| `lib/models/wallet_models.dart` | Safe immutable localized voucher title parsing |
| `lib/app/wallet_controller.dart` | Receipt matching to the frozen purchase |
| `lib/features/wallet/wallet_view.dart` | Purchase-specific notices and preserved retry after deactivation |
| `test/stage5_test.dart` | Existing twelve wallet checks plus four new regression tests |
| `../docs/fixtures/reward_policy_20_coins.json` | Owner-approved fixed-rate configuration and approval reference |
| `../scripts/configure-rewards.mjs` | Guarded, repeat-safe application of that exact immutable version |
| `../tests/reward-policy.test.mjs` | Exact approved rates/applicability and configuration guards |
| `tool/verify_wallet.mjs` | Read-only owner/privacy and earned-credit/debit consistency checks |
| `../docs/plans/2026-10-22-ui-phase-5-design.md` | Requirements, implementation sequence and completion evidence |
| `preview/phase5-redemption-retry.png` | Rebuilt app's real insufficient-balance retry sheet |
| `preview/phase5-wallet-bm-large.png` | Rebuilt app's phone wallet with BM, larger text and reduced motion |
| `preview/phase5-earned-100.png` | Five saved 20-coin credits funding the elder's first redemption |
| `preview/phase5-earned-voucher.png` | Saved earned voucher and 20-coin ledger entry in the final English phone build |
| `preview/phase5-earned-voucher-bm.png` | Same persisted earned voucher and ledger in BM |

## Run and verify

Use the existing local preview on `http://127.0.0.1:8090`; it serves the successful new release build. Full startup, demo accounts and walkthrough are in [LOCAL_BACKEND.md](LOCAL_BACKEND.md) and [STAGE5_VERIFICATION.md](STAGE5_VERIFICATION.md). Do not reset if preserving the current saved activity and check-in examples.

```powershell
# app/
.\preview.ps1 -Mode check
.\preview.ps1 -Mode build
# Only if no preview server is already listening on 8090:
.\preview.ps1 -Mode serve
# Repository root, after seed/reset and with emulators running:
npm.cmd run demo:configure-rewards
# Read-only, after the earned-redemption walkthrough for both demo recipients:
node app/tool/verify_wallet.mjs --expect-20-coin-demo
```

For a fresh walkthrough: configure the policy, complete five distinct participations for a recipient (coordinator-verified standalone attendance or separately confirmed companion sessions), open My rewards, confirm the 100-coin demo redemption, then refresh. Verify 20 coins per credited participation, one -100 debit, a saved DEMO code and the correct remaining balance. Family cannot read this financial history, and a participant cannot spend another person's coins. When checking the bare unconfigured foundation instead, use `--expect-default-demo` before configuration; it is deliberately incompatible with the earned-demo expectation.

Voice AI, notifications, merchant vouchers, cloud deployment and Tanya Dulu remain outside Phase 5. Index deployment is not proven by emulator checks. The current preview runs locally at `http://127.0.0.1:8090`.

# Stage 5: wallet UI integration

Historical PR #11 integration record. The owner's later 22 Oct approval enables 20-coin rewards; use [PHASE5_VERIFICATION.md](PHASE5_VERIFICATION.md) for the current configuration, earned-redemption results and startup steps. The unconfigured-policy and 84-test evidence below describes the original delivery.

Branch: `ui-stage5-wallet`, based on merged main `c178eb5`. The owner approved using the existing My rewards destination with the current Apple-inspired visual design and BM/EN. Backend Functions, rules, indexes, scripts and earning policy are unchanged. No cloud deployment is included.

## Connected experience

Actual elders and helpers can open My rewards to see their server-owned balance, participation reward outcomes, coin transactions, available mock vouchers and their saved DEMO codes. A pending reward is labelled separately from spendable coins. Missing, malformed or denied wallet data shows an unavailable/error state instead of an invented zero.

Review demo redemption opens an accessible confirmation sheet. Confirming calls `redeemDemoVoucher` with only the voucher ID, contract version and one immutable retry key. The server owns the 100-coin price, wallet debit and code. Duplicate taps are ignored; retry retains the same purchase; choosing again explicitly discards the failed intent. Current streams remain authoritative over an older receipt balance. Logout/role/township changes and permission errors clear money records and close open private confirmation content. Family/coordinators have no spending interface.

The default backend policy remains unconfigured. The real demo has zero coins and redemptions fail honestly with INSUFFICIENT_BALANCE. Positive-balance success is covered by the supplied **isolated UI-only** fixtures and isolated backend tests; it is not seeded into the user preview or presented as earned history. A full earned-credit-to-redemption rehearsal still requires the project owner's approved rates/eligibility/applicability and backend-owned configuration.

## Changed-file guide

| File | Purpose |
| --- | --- |
| `lib/models/wallet_models.dart` | Typed wallet, ledger, reward outcome, catalogue, redemption and callable result; timestamps and safe coin values |
| `lib/data/wallet_repository.dart`, `firebase_backend_repository.dart` | Exact owner/township queries and redemption envelope |
| `lib/app/wallet_controller.dart`, `preview_controller.dart` | Five scoped streams, immutable purchase retry, receipt/stream ordering and privacy cleanup |
| `lib/features/wallet/wallet_view.dart`, `features/connected/connected_home.dart` | My rewards, readable history, demo catalogue/codes and guarded confirmation sheet |
| `lib/data/backend_failure.dart`, `lib/app/app_shell.dart`, `features/community/attendance_views.dart` | Stable localized wallet errors and current connected-feature labels |
| `test/stage5_test.dart` | Twelve model/controller/widget tests, including isolated elder/helper redemption and responsive BM UI |
| `tool/verify_wallet.mjs` | Read-only six-account financial query/privacy verification |

## Verification on 22 October 2026 (Malaysia)

- Backend TypeScript build, **13 unit tests** and **84 integration/rules tests** passed against the running local emulators, including all 17 Stage 5 scenarios and earlier-stage regressions. The integration suite resets only disposable demo fixtures and cleans up its synthetic approved policies.
- Flutter analyze is clean; **84 Flutter tests** passed, including the 12 new wallet tests. All **7 browser-device/startup tests** passed.
- The six-account verifier passed **52 read-only wallet checks**, including exact sorted owner/township queries, family/other-participant denial, policy privacy, pending-only reward claims, and zero balances/ledger/redemptions.
- Browser baseline: the actual elder's Saya OK updated permitted family status, and the existing coordinator attendance review saved a verified activity and a pending reward claim with no coins.
- Release web build passed in **90 seconds**. Actual browser wallet walkthrough passed: elder zero balance, saved pending claim, confirmed insufficient-balance response and same-purchase retry, independent helper wallet, refresh persistence and permitted family activity history without a wallet destination. The read-only verifier passed all 52 checks again after those attempts, confirming no debit or voucher issuance.
- Actual phone BM/larger-text/gentler-motion/solid-navigation views were inspected; English/default preferences were restored afterward. Elder, helper and family browser sessions had no captured console errors. Coordinator's server-owned role retains its operational destinations rather than a spending interface.

Screenshot evidence: [desktop helper wallet](preview/stage5-helper-wallet.png), [phone insufficient balance and retry](preview/stage5-insufficient-balance.png), [BM phone wallet with larger text](preview/stage5-phone-bm.png), and [saved pending reward](preview/stage5-pending-reward.png).

The initial focused responsive test exposed a test-driver scroll alignment issue beneath the floating toolbar; the driver now centers the visible button text. The focused rerun and full suite passed. No unresolved analyzer/test failure remains in the results above.

## Preview left ready

The running release app is at `http://127.0.0.1:8090`. Separate elder and helper tabs are on My rewards; linked family can inspect the verified past activity, and a coordinator tab remains available. Main elder Saya OK was saved at 12:08 MYT on 22 October. The seeded past activity was verified at 12:24 MYT with the note “Verified against the synthetic demo organizer roster for Stage 5 integration testing.” It has one pending reward outcome, a zero balance, and no coin transaction or voucher. The helper has a separate zero wallet and no invented participation outcome. A ready assigned phone session remains available to try the two-person confirmation flow.

Do not reset if you want to retain these records. Final real balances are zero and no earning policy was activated. The backend suite's synthetic success policies were isolated test data and were cleaned up before browser acceptance.

## Start and try

Keep the running emulators and the preview on port 8090. Full first-time setup is in [LOCAL_BACKEND.md](LOCAL_BACKEND.md). If stopped, from the repository root:

```powershell
$env:JAVA_HOME='C:\Users\user\.jdks\openjdk-25.0.1'
$env:FUNCTIONS_DISCOVERY_TIMEOUT='60'
$env:FIREBASE_EMULATORS_PATH=Join-Path (Get-Location).Path '.cache/firebase/emulators'
npm.cmd run emulators
# A separate terminal, only for a fresh disposable walkthrough:
npm.cmd run demo:reset
# App terminal:
cd app
.\preview.ps1 -Mode build
# Start serving only if 8090 is free:
.\preview.ps1 -Mode serve
```

Open `http://127.0.0.1:8090`. Demo passwords are `EmasCare-local-2026!`. Reset may invalidate an existing sign-in. Avoid reset if preserving your current activity/session examples.

1. Sign in as `elder@emascare.test` → My rewards. Confirm the saved zero balance, a pending participation outcome after a verified attendance, and empty coin/voucher histories.
2. Review the 100-coin mock voucher → Confirm demo redemption. Expect the clear not-enough-coins error and unchanged balance. Retry uses the same purchase; Stop retrying allows a new intent. Close the sheet and refresh: server state is preserved.
3. Use `helper@emascare.test` in a separate tab. The wallet belongs to that helper, with no elder financial history. A completed two-person session can create that helper's own pending claim; it does not grant access to the elder wallet.
4. Family daily-sharing and booking consents do not grant wallet access. Family's fourth destination stays Community and coordinator's stays People; neither exposes a proxy spending action. Check permitted family activity history independently.
5. Try BM, larger text, gentler motion and solid navigation. Wallet and redemption layouts are covered at 320/390/768/1440 widths. The UI labels every voucher/code as demo only, with no merchant fulfilment.

Repeat checks:

```powershell
# app/
.\preview.ps1 -Mode check
.\preview.ps1 -Mode build
# root, read-only; --expect-default-demo additionally expects a main elder pending claim:
node app/tool/verify_wallet.mjs --expect-default-demo
# root, backend; integration tests reset disposable fixtures:
npm.cmd run build
npm.cmd run test:unit
npm.cmd run test:integration
```

No production deployment/index check or approved-rate earned-credit rehearsal is claimed by these emulator results.

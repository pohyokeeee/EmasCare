# Stage 5: connected My rewards

The owner approved connecting the existing My rewards destination, keeping the Apple-inspired forest-green/warm-white Manrope design, BM/EN and accessibility settings. Work on `ui-stage5-wallet` from merged main `c178eb5`. Publication was requested after verification. Backend Functions, rules, indexes, scripts and policy configuration stay unchanged.

## Implementation and acceptance

1. Add typed wallet, claim, ledger, voucher and redemption models. Use exact scoped owner/township streams and the version 1 `redeemDemoVoucher` envelope. Normalize Firestore and ISO timestamps; reject malformed money records.
2. Bind a wallet controller only for the actual authenticated elder/helper. Clear subscriptions, money records, retry commands and open confirmation views on logout, profile/scope change or permission failure. Keep streams authoritative over replayed callable balances. One immutable intent/key per confirmed purchase, retained across retries; ignore duplicate taps and late responses after scope loss.
3. Replace the connected-mode placeholder under My rewards with saved balance, reward outcomes, coin transactions, mock voucher catalogue and owned demo codes. Use the existing responsive surfaces, instant press feedback and accessible modal sheet. Separate pending outcomes from earned coins. Missing/failed wallet reads are unavailable, never fabricated zero balances. Confirm the 100-coin demo purchase; show server insufficient-balance errors and honest loading/empty/retry states.
4. Add meaningful fixture/controller/widget checks, including isolated UI-only sufficient-balance redemption, immutable retries/duplicate taps, stale receipts, logout/permission cleanup, role denial, all claim outcomes and BM/larger text at phone/tablet/desktop widths. Run Flutter analyze/tests, JS startup tests and release build. The current backend build, 13 unit tests and 84 emulator integration/rules checks already passed with unchanged backend sources.
5. Verify real browser elder/helper wallets, zero-balance redemption failure, a verified attendance's pending claim, refresh, consent-independent finance privacy and previous check-in/attendance flows. Leave the local preview ready with exact startup/manual steps and screenshots.

## Policy and scope

The default policy stays unconfigured and wallets stay zero until actual earning eligibility/rates/applicability are approved. Do not seed positive balances, activate the draft policy or claim pending rewards as earnings. Successful redemption UI is exercised only with the supplied isolated test fixture; backend configured-policy success and credit/debit races are covered by B's isolated tests. The mock voucher costs 100 coins and issues a DEMO code, with no merchant fulfilment. Family/coordinators cannot spend for another person. No new navigation destination, aggregate reports, voice feature or cloud deployment is included.

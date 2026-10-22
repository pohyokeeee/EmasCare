# Phase 5 completion and audit

The owner requested Phase 5 on `ui-phase-5` with Apple-design UI guidance and testing. This branch starts at merged main `874afa3`, which already includes the approved My rewards design and Stage 5 wallet integration from PR #11. Preserve that design and the existing BM/EN, accessibility, authentication and privacy behavior. No cloud deployment is included.

## Requirements and evidence

| Requirement | Completion evidence |
| --- | --- |
| Exact branch `ui-phase-5`, current merged UI/backend | Git branch, base and diff |
| Saved own wallet, participation outcomes, ledger and demo vouchers | Existing scoped adapter/controller, Flutter tests and live emulator browser |
| Confirmed redemption, immutable retry and current server balance | Same-key tests, real zero-balance error, isolated funded success and any approved-policy browser rehearsal |
| Apple-style clear, accessible and predictable UI | Existing green/warm-white design, instant press feedback, reduced motion and BM/larger-text views |
| Missing translation must not crash a card | Reproduced regression; fall back between BM/EN and reject unusable titles in the parser |
| A receipt must belong to the confirmed voucher | Reproduced regression; reject a mismatched voucher without announcing success |
| New purchase confirmation cannot show old success | Reproduced widget regression; keep previous purchase notice on the wallet only |
| Deactivation does not hide an existing purchase retry | Reproduced widget regression; preserve immutable retry inside the review sheet; backend remains authoritative |
| Earning amounts, eligibility and historical applicability | Actual owner decision, backend-owned approved policy, evidence-backed credits and no duplicate credit |
| Full earn-to-redemption demo | Approved-rate verified participations, own ledger/balance, 100-coin mock debit/code, refresh and privacy checks |

## Work sequence

1. Reuse and audit the approved UI already merged into main; reproduce uncovered errors before fixes.
2. Fix translation parsing, receipt matching and purchase-specific feedback/retry. Retain the current surfaces and confirmation controls.
3. Run focused and full Flutter checks, JS startup/device tests, release build and real browser regression. Backend accounting is already implemented; do not change Functions/rules/indexes or activate an invented policy.
4. Apply the owner's subsequent 22 Oct decision: 20 coins for every supported verified activity/helping session, for both roles, including earlier verified pending participation. Version this configuration, apply it only through the guarded local setup command, and reconcile using existing verified-source accounting. Preserve immutable policy versions and reject another active policy rather than silently replacing it.
5. Record current results, screens and any remaining policy-dependent gaps honestly. Completion of the full requested earning journey is not established by a zero-balance walkthrough alone.

## Owner decision and earned-coins evidence

The owner instructed: "Proceed with Award to all activities, 20 coins for one activities". This fixes all five canonical actions at 20 coins for elders and helpers, replacing the earlier proposed role difference. The all-activities scope includes earlier verified pending records. Keep the generic unknown-rate template as a draft; install the distinct approved `owner-20-all-v1` configuration. Daily check-ins are not activity participations.

The actual local rehearsal now covers all five actions for both roles, separate participant confirmations, earlier pending recovery, unchanged first verification times, repeated-confirmation/attendance deduplication, both recipients' earned 100-coin Flutter redemptions and repeat configuration/reconciliation without extra credits. No opening balance or completed history is seeded. Current detailed results and manual reproduction steps are in `app/PHASE5_VERIFICATION.md`.

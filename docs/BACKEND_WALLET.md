# Backend Stage 5: configured rewards, wallets and mock redemption

Branch: `backend-rewards-wallet`, based on merged Stage 4 commit `adb1b63`. Developer A owns every Flutter screen, coordinator UI, shared model and repository adapter. This stage changes backend code, rules/indexes, tests and handover artifacts only. No cloud service is provisioned or deployed.

## Current policy status

On 22 Oct 2026 the owner approved **20 coins per verified activity/helping session for both elders and helpers**, across all five supported actions. This replaces the earlier suggestion of different role rates. The "all activities" instruction is applied to existing verified pending participations as well as new ones. Daily Saya OK check-ins are not activity participations and remain outside the existing reward engine.

The versioned [approved 20-coin configuration](fixtures/reward_policy_20_coins.json) records this decision. With local emulators running, apply it and reconcile verified pending records with `npm.cmd run demo:configure-rewards`. It changes only local configuration through the existing exact-project/loopback guard; it creates pending monthly claims but does not make coins spendable before the next MYT month. Repeating it is safe; an existing conflicting approved version or different active policy is rejected.

`activity_attendance`, `walk_with_me`, `sit_with_me`, `carry_light_item`, and `phone_help` all create a 20-coin pending monthly claim for each actual verified beneficiary under the approved demo policy. The original first verification time determines the MYT reward month and next-month release date. A coordinator-triggered `settleDueMonthlyRewards` call makes due claims spendable; five distinct released participations fund one 100-coin voucher. Phone-help outing exclusion and unresolved standalone sit/carry outing definitions are separate from reward eligibility. The generic [policy review template](fixtures/reward_policy_template.json) remains a draft for future changes and is not installed.

Bare `demo:seed`/`demo:reset` deliberately restore an unconfigured policy, preserving the foundation and missing-policy tests. Run `demo:configure-rewards` afterward for this approved Phase 5 demo. For the presentation walkthrough only, run `npm.cmd run demo:wallet` after reset to add a clearly labeled 50-coin demo opening balance for the elder and helper; it is not an earned completion reward and must not be used as backend verification history. The original backend suite also exercises synthetic alternative policy values in isolated tests; those do not change this owner-approved configuration.

## What Developer A can connect

Use the [existing local Firebase setup](BACKEND_FOUNDATION.md): project `demo-emascare`, region `asia-southeast1`, Auth `127.0.0.1:9099`, Firestore `127.0.0.1:8080`, Functions `127.0.0.1:5001`. Connect emulators before using SDKs.

| Callable | Caller | Business input | Exact success `data` |
| --- | --- | --- | --- |
| `redeemDemoVoucher` | Actual elder/helper, spending their own wallet | `voucherId` | `{redemption,entryId,balance}` |
| `settleDueMonthlyRewards` | Same-township coordinator/operator | *(none)* | `{settledClaims,totalCoins,processedAt}` |

Every mutation input also contains `contractVersion:1` and an `idempotencyKey` kept across retries of the same confirmed action. Unknown fields are rejected. Owner, price, balance, code and all timestamps are server derived. Family and coordinator cannot redeem for an elder/helper, regardless of consent.

```json
{"contractVersion":1,"idempotencyKey":"redeem-001","voucherId":"voucher_demo"}
```

The monthly release trigger has no caller-supplied amount, recipient or date:

```json
{"contractVersion":1,"idempotencyKey":"settle-2026-11-01"}
```

It releases only claims whose backend `releaseAt` is at or before the server clock for the coordinator's township. A successful empty run returns `{contractVersion:1,data:{settledClaims:0,totalCoins:0,processedAt:"..."}}`.

For a deployed environment, `settleDueMonthlyRewardsScheduled` is also registered with Cloud Scheduler for `00:00` on the first day of each month in `Asia/Kuala_Lumpur`. It uses the same server-side settlement logic across all townships and accepts no client input. The local Functions emulator does not run scheduled Pub/Sub triggers, so the coordinator callable remains the deterministic demo/test path.

The active mock voucher costs the already agreed **100 coins**. The backend checks same township, `active:true`, `isDemo:true`, the configured 100-coin price, a valid own wallet and sufficient funds. Debit, immutable ledger entry, one mock redemption/code and receipt commit together. No merchant request or external voucher issuance occurs.

Success after callable transport unwrapping is `{contractVersion:1,data:{redemption:{...},entryId:"...",balance:0}}`, with the balance determined by the actual opening balance. `redemption` includes `id`, `ownerUid`, `townshipId`, `voucherId`, `costCoins`, `code`, `ledgerEntryId`, `issuedAt`, `isDemo:true`. Codes start with `DEMO-`.

Complete examples are in [stage5_wallet.json](fixtures/stage5_wallet.json). Default zero-wallet behavior is `INSUFFICIENT_BALANCE`. The successful elder/helper examples are isolated UI-only scenarios with a hypothetical 100-coin opening balance, **not for seeding**. The optional presentation setup uses a separate 50-coin `demo_opening_credit`, clearly marked as demo-only, so the voucher remains locked until the saved balance reaches 100. It does not claim that any completion earned those coins or approve an earning rate. This follows the separately shared contract's isolated redemption example boundary. The private full-contract files remain excluded from Git.

Same-key retries return the original saved redemption/result without another debit. Reusing that key for another voucher fails. A genuinely additional purchase requires a new key and funds. Concurrent purchases cannot overspend. Authorization and wallet scope are rechecked on every replay; a later catalog deactivation does not revoke an already issued same-key result. A replay's balance can be older than the current wallet stream.

## Completion rewards and immutable ledger

There is no client reward/grant endpoint. Rewards run inside the existing final companion-confirmation or coordinator attendance-verification transaction. Those callables retain their agreed response envelopes and do not expose the other participant's finances. Owners observe reward claims and wallet streams.

An activity occurrence is one canonical event, whether standalone or accompanied. Each actual beneficiary has one canonical participation. A standalone helping request is a different event only when it has no activity attendance. An accompanied activity does not also earn a second helping-session reward for the same person.

The backend selects one configured rule by canonical action and beneficiary role. Activity-linked assistance uses `activity_attendance`; standalone helping uses its task type. Several matching rules are ambiguous and remain pending rather than being added together. Check-ins are not supported reward actions. There is no four-session threshold or fixed monthly award; the only month-based rule is release on the next MYT calendar-month boundary.

| Outcome | Claim fields | Wallet/ledger effect |
| --- | --- | --- |
| Missing/unapproved/unknown/inapplicable or ambiguous policy | `pending_policy`, eligibility/amount/rule/rate fields null | None |
| Explicit approved exclusion | `ineligible`, `eligible:false`, `amountCoins:0`, approved rule ID/version and reason | None |
| Explicit approved eligible rate before release | `pending_monthly`, `eligible:true`, positive approved amount/rate, rule ID/version, `ledgerEntryId:null`, `rewardMonth`, `releaseAt` | None yet |
| Due monthly settlement | `credited`, `eligible:true`, immutable ledger reference and `releasedAt` | One credit |

The credit entry ID derives only from canonical participation identity, excluding retry key, evidence source, reporting month and policy version. Claim, ledger, wallet and domain completion commit in one transaction after all required reads. Repeated confirmation, evidence representations, a changed policy version or recovery cannot issue another credit. Existing credited/ineligible outcomes are terminal; financial correction/reversal is outside this demo contract.

`wallets/{uid}` has `ownerUid`, `townshipId`, nonnegative safe-integer `balance`, and `updatedAt`. Entries are immutable, server written records with `ownerUid`, `townshipId`, `type`, signed `amount`, `balanceAfter`, nullable `participationId`, `completionEventId`, `ruleId`, `ruleVersion`, `rateCoins`, `referenceId`, `createdAt`. Completion entries are written only during monthly settlement.

Reward entries use type `completion_reward` and link the event, participant, recipient, approved rule/version and actual rate. Their `referenceId` is the participation ID. Redemption entries use `voucher_redemption`, a negative 100-coin amount, null reward fields and a redemption ID reference. The backend rejects malformed ownership, negative/fractional/unsafe balances, overflow, and inconsistent existing financial records rather than adding an untracked credit.

## Backend-owned policy configuration

Policies and policy versions are inaccessible to clients, including coordinators. There is no public policy editor or approval endpoint.

- `rewardPolicies/{townshipId}` contains `townshipId`, `activeVersionId` (null while unconfigured), `updatedAt`.
- `rewardPolicyVersions/{versionId}` contains `townshipId`, `version`, `status:approved`, `approvedBy`, `approvalReference`, `approvedAt`, `effectiveFrom`, `effectiveUntil` (null or timestamp), and `rules[]`.
- Each rule has a unique `id`, canonical `action`, `role:elder/helper`, `eligible:true/false/null`, `rateCoins` (positive safe integer only for true, otherwise null), and a factual `reason`.
- Approval identity/reference must document the actual project decision. The effective interval is inclusive at `effectiveFrom`, exclusive at a non-null `effectiveUntil`, and applies to the participation's preserved first verification time. It is an explicit policy applicability range, not a monthly reward rule.

Store approval/effective dates as Firestore `Timestamp`, not JSON date strings. The local configuration command converts the approved JSON dates before writing. Do not repurpose an approved version for new terms; add a new version and explicitly choose applicability. Existing outcomes retain their original immutable ledger/rule/rate. The generic draft JSON remains a review artifact for future policy changes.

## Internal reconciliation and reset

With emulators running:

```powershell
npm.cmd run demo:reconcile-rewards
```

This guarded local command accepts no rates, recipients or policy arguments. It visits the known demo elders/helpers' participations and rechecks canonical event identity and actual verified attendance or mutually confirmed request evidence before applying an approved applicable policy. It is not exported as a callable and cannot target a live project. With no approved policy, it prints pending status and leaves balances unchanged. Use the coordinator-only `settleDueMonthlyRewards` callable to release claims whose `releaseAt` has arrived.

Concurrent settlement attempts use the same credit key and wallet transaction. A missing claim with an existing valid immutable credit entry is reconstructed without increasing balance again. A credited claim with a missing/conflicting ledger entry fails for investigation; it is not blindly credited again. Reconciliation does not rewrite completion timestamps or produce progress twice.

`npm.cmd run demo:reset` still operates only against the guarded local demo project. It removes known demo wallets' nested entries and owned redemptions, implemented-stage receipts and known source-derived completion records, then restores zero wallets and an unconfigured policy pointer. Run `npm.cmd run demo:wallet` afterward only when preparing the presentation walkthrough; it adds 50 demo coins and keeps the 100-coin redemption guard. Unrelated owners' financial records remain. Shared events with retained participants remain. Approved version documents are not globally deleted; the default pointer is cleared. Reset is an offline demo cleanup, not a production financial correction API.

`demo:seed` initializes a missing wallet but **preserves an existing wallet and its ledger**. It upserts other named fixtures and resets the default policy pointer to null. Use reset for a clean rehearsal; seeding must not zero a balance while retaining its financial history. Apply `demo:configure-rewards` after seed/reset to restore the approved 20-coin policy and settle earlier verified pending records safely.

## Queries and permissions

| View | Document/query |
| --- | --- |
| Own wallet | `wallets/{currentUid}` |
| Own ledger | `wallets/{currentUid}/entries`, `ownerUid == currentUid`, `townshipId == currentTownshipId`, order `createdAt DESC` |
| Own redemptions | `redemptions`, `ownerUid == currentUid`, `townshipId == currentTownshipId`, order `issuedAt DESC` |
| Own reward outcomes | `rewardClaims`, `beneficiaryUid == currentUid`, `townshipId == currentTownshipId`, order `verifiedAt DESC` |

Include both identity and township filters in financial list queries. Rules do not filter broad collections. The owner and same-township coordinator can read financial records; family and another participant cannot. A coordinator's read permission does not grant spending or direct writes. Policy/lock/receipt reads and every client financial write remain denied. Index definitions are included; emulators do not prove production indexes have been deployed.

## Errors and next actions

Use callable `code` and `details.reason` for localized adapter messages. Existing envelope/ID/key errors remain. Redemption adds `VOUCHER_NOT_FOUND` (`not-found`), `VOUCHER_NOT_AVAILABLE`, `INVALID_VOUCHER_PRICE`, `INSUFFICIENT_BALANCE`, `WALLET_REQUIRED`, `INVALID_WALLET_BALANCE`, `REDEMPTION_ACCOUNTING_CONFLICT` (`failed-precondition`), and `WALLET_ACCESS_DENIED`/`TOWNSHIP_NOT_ALLOWED` (`permission-denied`). Unauthorized callers receive `AUTH_REQUIRED`/`ROLE_NOT_ALLOWED`. Changed intent under a successful key returns `IDEMPOTENCY_KEY_REUSED`.

Reward/recovery consistency errors include `REWARD_ACCOUNTING_CONFLICT`, `REWARD_RECIPIENT_MISMATCH`, `COMPLETION_NOT_VERIFIED`, `INVALID_PARTICIPATION_LINK`, `INVALID_MONTHLY_REWARD` (`failed-precondition`). Missing approval is a persisted pending outcome, not a successful credit. Do not display a pending claim as an earned balance.

1. Stop existing emulators, then run `npm.cmd test`. It builds TypeScript and runs unit and emulator tests, including all prior-stage regressions, real authenticated redemption, both recipient roles, policy applicability, evidence checks, credit/debit and retry races, rollback, exact JSON agreement and reset preservation. Synthetic configured policies are isolated test data and cleaned up.
2. Start `npm.cmd run emulators`, then run `npm.cmd run demo:reset` in another terminal. For the presentation wallet, run `npm.cmd run demo:wallet`; each elder/helper wallet then shows 50 clearly labeled demo coins and redemption remains unavailable until 100. For backend verification, omit that command: before configuration, a completion remains pending and an empty wallet reports `INSUFFICIENT_BALANCE`. Run `npm.cmd run demo:configure-rewards`; that existing pending completion becomes a 20-coin `pending_monthly` claim. On or after the next MYT month boundary, a coordinator calls `settleDueMonthlyRewards`; only then do released credits fund a 100-coin demo voucher. Follow the current [Phase 5 verification](../app/PHASE5_VERIFICATION.md) for combined UI/backend results.
3. **Commit -> push `backend-rewards-wallet` -> create PR -> send Developer A the PR, this guide and the JSON fixtures.** They can connect wallet/ledger/claim/redemption streams and the redemption callable independently while approval remains pending. Joint Flutter integration is a separate check.
4. The owner-approved table is now versioned in `reward_policy_20_coins.json`. Phase 5 verification must use actual 20-coin credits from verified evidence, never a positive opening-balance seed. Continue Stage 6 with voice parsing, reports/blocking, warnings, due processing, cheers and sanitized summaries. Tanya Dulu remains future work.

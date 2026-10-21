# Backend Stage 5: configured rewards, wallets and mock redemption

Branch: `backend-rewards-wallet`, based on merged Stage 4 commit `adb1b63`. Developer A owns every Flutter screen, coordinator UI, shared model and repository adapter. This stage changes backend code, rules/indexes, tests and handover artifacts only. No cloud service is provisioned or deployed.

## Current policy status

Reward amounts, role/action eligibility and application to previously verified pending completions still need the project owner's approval. The default demo policy is **unconfigured**. No product earning rate or positive earning history is seeded. New valid completions remain recorded with pending claims and zero awarded coins until an approved applicable policy exists.

The configured reward engine, protected mock redemption and internal recovery path can be exercised in isolated emulator tests. Their successful tests use explicitly synthetic policy values and sufficient-balance scenarios, not approved product rates. The [policy review template](fixtures/reward_policy_template.json) is a draft with unknown eligibility/rates; it must not be activated as an approved policy.

To enable actual awards, agree elder/helper eligibility and coin amounts for `activity_attendance`, `walk_with_me`, `sit_with_me`, `carry_light_item`, and `phone_help`. Also agree the verification-time range covered by the policy, including whether existing pending participations qualify. Phone-help outing exclusion does not decide its reward eligibility. Standalone sit/carry outing definitions remain pending and separate from reward eligibility.

## What Developer A can connect

Use the [existing local Firebase setup](BACKEND_FOUNDATION.md): project `demo-emascare`, region `asia-southeast1`, Auth `127.0.0.1:9099`, Firestore `127.0.0.1:8080`, Functions `127.0.0.1:5001`. Connect emulators before using SDKs.

| Callable | Caller | Business input | Exact success `data` |
| --- | --- | --- | --- |
| `redeemDemoVoucher` | Actual elder/helper, spending their own wallet | `voucherId` | `{redemption,entryId,balance}` |

Every mutation input also contains `contractVersion:1` and an `idempotencyKey` kept across retries of the same confirmed action. Unknown fields are rejected. Owner, price, balance, code and all timestamps are server derived. Family and coordinator cannot redeem for an elder/helper, regardless of consent.

```json
{"contractVersion":1,"idempotencyKey":"redeem-001","voucherId":"voucher_demo"}
```

The active mock voucher costs the already agreed **100 coins**. The backend checks same township, `active:true`, `isDemo:true`, the configured 100-coin price, a valid own wallet and sufficient funds. Debit, immutable ledger entry, one mock redemption/code and receipt commit together. No merchant request or external voucher issuance occurs.

Success after callable transport unwrapping is `{contractVersion:1,data:{redemption:{...},entryId:"...",balance:0}}`, with the balance determined by the actual opening balance. `redemption` includes `id`, `ownerUid`, `townshipId`, `voucherId`, `costCoins`, `code`, `ledgerEntryId`, `issuedAt`, `isDemo:true`. Codes start with `DEMO-`.

Complete examples are in [stage5_wallet.json](fixtures/stage5_wallet.json). Default zero-wallet behavior is `INSUFFICIENT_BALANCE`. The successful elder/helper examples are isolated UI-only scenarios with a hypothetical 100-coin opening balance, **not for seeding**. They do not claim that any completion earned that balance or approve an earning rate. This follows the separately shared contract's isolated redemption example boundary. The private full-contract files remain excluded from Git.

Same-key retries return the original saved redemption/result without another debit. Reusing that key for another voucher fails. A genuinely additional purchase requires a new key and funds. Concurrent purchases cannot overspend. Authorization and wallet scope are rechecked on every replay; a later catalog deactivation does not revoke an already issued same-key result. A replay's balance can be older than the current wallet stream.

## Completion rewards and immutable ledger

There is no client reward/grant endpoint. Rewards run inside the existing final companion-confirmation or coordinator attendance-verification transaction. Those callables retain their agreed response envelopes and do not expose the other participant's finances. Owners observe reward claims and wallet streams.

An activity occurrence is one canonical event, whether standalone or accompanied. Each actual beneficiary has one canonical participation. A standalone helping request is a different event only when it has no activity attendance. An accompanied activity does not also earn a second helping-session reward for the same person.

The backend selects one configured rule by canonical action and beneficiary role. Activity-linked assistance uses `activity_attendance`; standalone helping uses its task type. Several matching rules are ambiguous and remain pending rather than being added together. Check-ins are not supported reward actions. No monthly threshold, four-session requirement, month-end award or monthly reward limit exists.

| Outcome | Claim fields | Wallet/ledger effect |
| --- | --- | --- |
| Missing/unapproved/unknown/inapplicable or ambiguous policy | `pending_policy`, eligibility/amount/rule/rate fields null | None |
| Explicit approved exclusion | `ineligible`, `eligible:false`, `amountCoins:0`, approved rule ID/version and reason | None |
| Explicit approved eligible rate | `credited`, `eligible:true`, positive approved amount/rate, rule ID/version, immutable ledger reference | One credit |

The credit entry ID derives only from canonical participation identity, excluding retry key, evidence source, reporting month and policy version. Claim, ledger, wallet and domain completion commit in one transaction after all required reads. Repeated confirmation, evidence representations, a changed policy version or recovery cannot issue another credit. Existing credited/ineligible outcomes are terminal; financial correction/reversal is outside this demo contract.

`wallets/{uid}` has `ownerUid`, `townshipId`, nonnegative safe-integer `balance`, and `updatedAt`. Entries are immutable, server written records with `ownerUid`, `townshipId`, `type`, signed `amount`, `balanceAfter`, nullable `participationId`, `completionEventId`, `ruleId`, `ruleVersion`, `rateCoins`, `referenceId`, `createdAt`.

Reward entries use type `completion_reward` and link the event, participant, recipient, approved rule/version and actual rate. Their `referenceId` is the participation ID. Redemption entries use `voucher_redemption`, a negative 100-coin amount, null reward fields and a redemption ID reference. The backend rejects malformed ownership, negative/fractional/unsafe balances, overflow, and inconsistent existing financial records rather than adding an untracked credit.

## Backend-owned policy configuration

Policies and policy versions are inaccessible to clients, including coordinators. There is no public policy editor or approval endpoint.

- `rewardPolicies/{townshipId}` contains `townshipId`, `activeVersionId` (null while unconfigured), `updatedAt`.
- `rewardPolicyVersions/{versionId}` contains `townshipId`, `version`, `status:approved`, `approvedBy`, `approvalReference`, `approvedAt`, `effectiveFrom`, `effectiveUntil` (null or timestamp), and `rules[]`.
- Each rule has a unique `id`, canonical `action`, `role:elder/helper`, `eligible:true/false/null`, `rateCoins` (positive safe integer only for true, otherwise null), and a factual `reason`.
- Approval identity/reference must document the actual project decision. The effective interval is inclusive at `effectiveFrom`, exclusive at a non-null `effectiveUntil`, and applies to the participation's preserved first verification time. It is an explicit policy applicability range, not a monthly reward rule.

Store approval/effective dates as Firestore `Timestamp`, not JSON date strings. Do not repurpose an approved version for new terms; add a new version and explicitly choose applicability. Existing outcomes retain their original immutable ledger/rule/rate. The draft JSON is a review artifact and deliberately fails approved-policy requirements until the missing decisions and metadata are supplied by the backend owner.

## Internal reconciliation and reset

With emulators running:

```powershell
npm.cmd run demo:reconcile-rewards
```

This guarded local command accepts no rates, recipients or policy arguments. It visits the known demo elders/helpers' participations and rechecks canonical event identity and actual verified attendance or mutually confirmed request evidence before applying an approved applicable policy. It is not exported as a callable and cannot target a live project. With no approved policy, it prints pending status and leaves balances unchanged.

Concurrent settlement attempts use the same credit key and wallet transaction. A missing claim with an existing valid immutable credit entry is reconstructed without increasing balance again. A credited claim with a missing/conflicting ledger entry fails for investigation; it is not blindly credited again. Reconciliation does not rewrite completion timestamps or produce progress twice.

`npm.cmd run demo:reset` still operates only against the guarded local demo project. It removes known demo wallets' nested entries and owned redemptions, implemented-stage receipts and known source-derived completion records, then restores zero wallets and an unconfigured policy pointer. Unrelated owners' financial records remain. Shared events with retained participants remain. Approved version documents are not globally deleted; the default pointer is cleared. Reset is an offline demo cleanup, not a production financial correction API.

`demo:seed` initializes a missing wallet but **preserves an existing wallet and its ledger**. It upserts other named fixtures and resets the default policy pointer to null. Use reset for a clean rehearsal; seeding must not zero a balance while retaining its financial history. After policy approval, an explicit configuration/seed update and rate-consistent historical fixture work are still needed for an earned-coins redemption rehearsal.

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

Reward/recovery consistency errors include `REWARD_ACCOUNTING_CONFLICT`, `REWARD_RECIPIENT_MISMATCH`, `COMPLETION_NOT_VERIFIED`, `INVALID_PARTICIPATION_LINK` (`failed-precondition`). Missing approval is a persisted pending outcome, not a successful credit. Do not display a pending claim as an earned balance.

1. Stop existing emulators, then run `npm.cmd test`. It builds TypeScript and runs unit and emulator tests, including all prior-stage regressions, real authenticated redemption, both recipient roles, policy applicability, evidence checks, credit/debit and retry races, rollback, exact JSON agreement and reset preservation. Synthetic configured policies are isolated test data and cleaned up.
2. Start `npm.cmd run emulators`, then run `npm.cmd run demo:reset` in another terminal. Complete a session or verify attendance and confirm the default pending claim/zero wallet. Attempt redemption and handle `INSUFFICIENT_BALANCE`. An earned-credit success walkthrough awaits approved rates and consistent history.
3. **Commit -> push `backend-rewards-wallet` -> create PR -> send Developer A the PR, this guide and the JSON fixtures.** They can connect wallet/ledger/claim/redemption streams and the redemption callable independently while approval remains pending. Joint Flutter integration is a separate check.
4. Agree and configure the outstanding reward table/applicability, rerun configured-policy checks with those exact approved values, and prepare honest earned-credit fixtures before calling the full reward demo complete. Continue Stage 6 with voice parsing, reports/blocking, warnings, due processing, cheers and sanitized summaries. Tanya Dulu remains future work.

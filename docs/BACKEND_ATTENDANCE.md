# Backend Stage 4: standalone activity attendance

Branch: `backend-activity-attendance`, based on Stage 3 commit `1d8a5d9`. This implements the agreed contract v1, revision 2 standalone attendance flow. Developer A owns all Flutter screens, coordinator UI, shared models and the repository adapter. Backend verification here does not verify Flutter integration. No cloud service is provisioned or deployed.

## What Developer A can connect

Use the [Stage 1 emulator configuration and accounts](BACKEND_FOUNDATION.md): project `demo-emascare`, region `asia-southeast1`, Auth `127.0.0.1:9099`, Firestore `127.0.0.1:8080`, Functions `127.0.0.1:5001`. The [Stage 3 session APIs](BACKEND_SESSIONS.md) retain their success response shapes.

| Callable | Signed-in caller | Business input | Exact `data` result |
| --- | --- | --- | --- |
| `submitActivityAttendance` | Actual elder, for themselves | `activityId` | `{attendance}` |
| `reviewActivityAttendance` | Same-township coordinator | `attendanceId`, `decision`, `verificationMethod`, `note` | `{attendance}` |

All mutations require `contractVersion:1` and a nonempty `idempotencyKey` of at most 128 characters. The success envelope after Firebase callable transport unwrapping is `{contractVersion:1,data:{attendance:{...}}}`. Unknown fields are rejected. Elder identity, household, township, source IDs and all timestamps come from the server. Do not send `elderId`, `status`, completion IDs, reward amounts or a client timestamp.

Complete matching inputs and response examples are in [stage4_attendance.json](fixtures/stage4_attendance.json). These are synthetic UI scenarios checked against service responses using an internal test clock. They are not verified-history seed instructions. The private full-contract files remain excluded from Git.

An elder submission:

```json
{
  "contractVersion": 1,
  "idempotencyKey": "attendance-submit-001",
  "activityId": "activity_demo_attendance"
}
```

Coordinator verification:

```json
{
  "contractVersion": 1,
  "idempotencyKey": "attendance-review-001",
  "attendanceId": "ID_FROM_SUBMISSION_OR_REVIEW_QUEUE",
  "decision": "verify",
  "verificationMethod": "organizer_roster",
  "note": "Matched the organizer attendance roster."
}
```

`decision` is `verify` or `reject`. Verification requires `coordinator_observed` or `organizer_roster` and a factual note. The coordinator must actually observe attendance or check a trusted organizer roster. The endpoint records that verification; it does not fetch an external roster or independently prove presence. Rejection requires `verificationMethod:null` and a reason in `note`. Notes must contain 1–500 characters, with whitespace trimmed. No uploads, QR flow, family proxy claim or helper standalone claim is added.

## Records and states

Only in-person activity occurrences that have ended may be submitted or reviewed. The exact end timestamp is allowed. A future/ongoing activity fails with `ACTIVITY_NOT_FINISHED`. Activity, elder, current household and reviewer township must agree. An elder can submit without a pairing or family consent. Family and helper accounts cannot submit on their behalf; only a current coordinator can review.

One canonical attendance record exists per activity occurrence and elder. `data.attendance` has these fields:

| Fields | Meaning |
| --- | --- |
| `id`, `townshipId`, `householdId`, `activityId`, `elderId` | Server-derived identity and permission scope |
| `mode`, `status`, `linkedRequestId` | `standalone`; `submitted/verified/rejected`; null for standalone attendance |
| `submittedAt`, `verifiedAt` | Server submission time; verification time or null |
| `verificationMethod`, `reviewedBy`, `reviewedAt`, `reviewNote` | Null on submission; trusted method or null on rejection, reviewer UID, review time and factual note after review |
| `completionEventId`, `participationId` | Null until verified; canonical completion references afterward |
| `createdAt`, `updatedAt` | Server timestamps |

Firestore stores `Timestamp`; callable responses and JSON fixtures use UTC ISO strings. IDs are opaque to Flutter; use returned/query document IDs rather than computing hashes.

```text
submitted -> verified
submitted -> rejected
```

Self-submission creates no completion event, participation, reward claim or outing marker. Verification atomically records the review, verified attendance, canonical event/elder participation, one outing marker, a pending-policy reward claim, the activity/elder lock and the command receipt. Rejection records review metadata but creates none of those verified effects.

Verified and rejected reviews are terminal. Successful same-key retries return the stored original result; changed intent under that key fails. A new review key against terminal standalone attendance fails with `ATTENDANCE_ALREADY_REVIEWED`, even for the same decision. Repeated submissions with new keys return the existing canonical attendance and preserve its first submission/review metadata. To make another eligible participation, the elder needs a different activity occurrence.

Receipts do not bypass current permissions. Current role, activity/elder township and household membership are checked again on replay. An old submission receipt may still describe `submitted` after the current stream is `verified`; it does not revert the stored review. Use streams for current state.

## Shared identity with companion sessions

Companion requests and standalone attendance contend on the same backend activity/elder lock. A requested, assigned, accepted, in-progress or partly confirmed companion request returns `ATTENDANCE_MANAGED_BY_SESSION` from standalone submission. Review rechecks the source/lock and cannot replace a missing participant confirmation. Cancelling a companion request releases its control and allows standalone submission after the activity ends.

A completed companion session already has verified attendance. A later elder submission returns that same representation. A valid coordinator verify call also returns it unchanged, retaining `verificationMethod:mutual_session_confirmation`, null review metadata and its existing completion identity. A reject call cannot reverse it. Neither route creates another participation or claim.

The shared completion writer identifies an activity event by occurrence ID, and a participation/claim/marker by event plus beneficiary UID. It preserves existing first verification times and existing claims while merging evidence references. Different elders at the same activity share one event and have separate participations. Accompanied attendance additionally has the actual helper's separate participation; standalone elder attendance invents no helper.

The request API additionally returns `ATTENDANCE_ALREADY_SUBMITTED` if existing submitted/rejected attendance owns that occurrence. Verified attendance still returns `ACTIVITY_ALREADY_COMPLETED`. This protects the shared lock even if source schedules change or requests race across timing boundaries. Existing Stage 3 success envelopes remain unchanged.

Reward rates and detailed eligibility are still unapproved. Claims remain `pending_policy` with `eligible`, `amountCoins`, `rateCoins`, `ruleId`, `ruleVersion` and `ledgerEntryId` null. Wallet balances and ledgers are unchanged. There is no monthly threshold or public award function. Stage 5 will implement rewards/redemption after policy agreement; aggregate progress/reporting APIs remain Stage 6. A verified physical activity has an internal `counts` marker for its elder participation.

## Read queries and consent

All browser writes remain denied, including for coordinators. Use callables for mutations and scoped Firestore streams for current state.

| View | Query |
| --- | --- |
| Elder attendance history, including submitted/rejected | `activityAttendances`, `elderId == currentUid`, order `createdAt DESC` |
| Linked family attendance history | `activityAttendances`, `elderId == selectedElderId`, `householdId == currentHouseholdId`, order `createdAt DESC` |
| Coordinator submitted review queue | `activityAttendances`, `townshipId == currentTownshipId`, `status == submitted`, order `submittedAt ASC` |
| Own participation or claim history | `participations` or `rewardClaims`, `beneficiaryUid == currentUid`, `townshipId == currentTownshipId`, order `verifiedAt DESC` |

The existing family history query ordered by `verifiedAt DESC` remains available, but `createdAt` gives a more useful ordering for pending claims. Companion-derived records have null `submittedAt`; the submitted review queue excludes them by status. Composite definitions are included; local emulators do not verify deployed production indexes.

Family attendance reads require current **sharing** consent. Booking consent alone grants no attendance read or verification authority. Family cannot read participation/reward claims or wallets. Helpers cannot read elders' standalone attendance. The actual elder and same-township coordinator can read the operational record. Raw canonical events, progress markers and backend locks remain private.

Watch the household access flags and clear/unsubscribe affected family views when sharing is withdrawn. An idle SDK stream can retain a previously permitted snapshot; a fresh server request and the next changed result are permission checked. See the [Stage 3 consent listener details](BACKEND_SESSIONS.md). Broad collection queries are denied rather than filtered into safe results.

## Error reasons

Use Firebase callable `code` and `details.reason` for localized UI messages.

| Code | Relevant reasons |
| --- | --- |
| `unauthenticated` | `AUTH_REQUIRED` |
| `permission-denied` | `PROFILE_REQUIRED`, `ROLE_NOT_ALLOWED`, `TOWNSHIP_NOT_ALLOWED`, `UNRELATED_HOUSEHOLD`, `ELDER_ACCESS_DENIED`, `ATTENDANCE_ACCESS_DENIED` |
| `invalid-argument` | `UNSUPPORTED_CONTRACT_VERSION`, `INVALID_PAYLOAD`, `UNKNOWN_FIELD`, `INVALID_IDEMPOTENCY_KEY`, `INVALID_ID`, `INVALID_REVIEW_DECISION`, `INVALID_VERIFICATION_METHOD`, `INVALID_REVIEW_NOTE` |
| `not-found` | `ACTIVITY_NOT_FOUND`, `ATTENDANCE_NOT_FOUND` |
| `failed-precondition` | `ELDER_HOUSEHOLD_REQUIRED`, `ACTIVITY_NOT_FINISHED`, `ACTIVITY_NOT_IN_PERSON`, `INVALID_ACTIVITY_SCHEDULE`, `INVALID_ATTENDANCE_LINK`, `ATTENDANCE_MANAGED_BY_SESSION`, `ATTENDANCE_ALREADY_REVIEWED`, `ACTIVITY_ALREADY_COMPLETED`, `ATTENDANCE_ALREADY_SUBMITTED` |
| `already-exists` | `IDEMPOTENCY_KEY_REUSED` |

## Local walkthrough and stage handover

1. Stop any existing emulator suite, then run `npm.cmd test`. It builds TypeScript, runs unit checks, starts Auth/Firestore/Functions emulators, runs new attendance and prior-stage tests, then shuts them down. Coverage includes actual authenticated callables/client reads, time boundaries with internal clocks, role/source/consent checks, terminal review races, request/attendance locking, canonical deduplication, pending claims, exact JSON agreement and selective reset.
2. Start `npm.cmd run emulators`. In a second terminal, run `npm.cmd run demo:reset`. This seeds `activity_demo_attendance`, a synthetic in-person occurrence ending about 15 minutes before reset, with **no claimed or verified attendance**. The two upcoming Stage 3 activities remain. No client clock override or public backdating endpoint exists.
3. Sign in as `solo@emascare.test` / `EmasCare-local-2026!` and submit `activity_demo_attendance`. Confirm the record is submitted and has no reward/progress. Sign in separately as `coordinator@emascare.test`, check the review queue and verify only after checking attendance evidence. Inspect the verified record and the elder's pending claim. Use another elder or reset to demonstrate rejection.
4. For family visibility, use `elder@emascare.test` and linked `family@emascare.test`; `elder_solo` has no linked family. Withdraw sharing and check that the family view clears. Booking consent does not replace sharing.
5. Reset now also clears the two demo elders' standalone attendance, shared activity/elder locks, derived participations/claims/markers, empty completion events and Stage 4 receipts. Other elders' attendance/participations and shared events with remaining participants are preserved. Reset is an offline demo operation, not a production cleanup endpoint. Seed alone upserts snapshots; use reset for a fresh walkthrough.
6. **Commit Stage 4 -> push `backend-activity-attendance` -> create a PR -> send Developer A the PR link, this guide and JSON fixtures.** This branch builds on Stage 3, so merge Stage 3 before merging Stage 4. Keep any Stage 3 integration fixes synchronized into this branch. Do not wait until all stages are done to share a tested stage.
7. Jointly test elder submission -> coordinator review -> permitted history. Send exact callable name, `code` and `details.reason` for problems. Continue Stage 5 after agreeing role/action eligibility, coin rates and treatment of pending completions. Phone-help reward eligibility and sit/carry outing definitions remain pending; Tanya Dulu stays future work.

# Backend Stage 3: companion requests and session completion

Branch: `backend-companion-sessions`, based on Stage 2 commit `a150b9a`. This implements the agreed contract v1, revision 2 companion APIs. Developer A owns all Flutter screens, coordinator UI, Dart models and the repository adapter. No Flutter files are changed here. These are local emulator APIs; no cloud deployment has happened.

## Connect these APIs

Use the [Stage 1 emulator configuration and six demo accounts](BACKEND_FOUNDATION.md): project `demo-emascare`, region `asia-southeast1`, Auth `127.0.0.1:9099`, Firestore `127.0.0.1:8080`, Functions `127.0.0.1:5001`. Callables require Firebase Authentication.

Every mutation input contains `contractVersion: 1` and a nonempty `idempotencyKey` of at most 128 characters. Every success after callable transport unwrapping is `{contractVersion:1,data:{...}}`. Reuse the key for network retries; use a new key for a new action. Unknown fields are rejected. The server determines identity, township, household, state, timestamps and completion/reward identifiers.

| Callable | Caller | Business input fields | Exact `data` result |
| --- | --- | --- | --- |
| `setHelperAvailability` | Helper, themselves | `available`, `slots` | `{helperProfile}` |
| `createRequest` | Actual elder or linked family with current booking consent | `elderId`, `activityId`, `placeId`, `startsAt`, `endsAt`, `taskType`, `preferredLanguage`, `preferredHelperGender` | `{request}` |
| `assignRequest` | Same-township coordinator | `requestId`, `pairingId` | `{request}` |
| `transitionRequest` | Authorized participant/coordinator as below | `requestId`, `action` | `{request}` |

Copy complete inputs and responses from [stage3_sessions.json](fixtures/stage3_sessions.json). These are synthetic successive UI states, including a completed activity and two pending-policy claims. They are checked against the real service using an internal test clock. They are not seed instructions. The private full-contract files remain excluded from Git.

Availability example:

```json
{"contractVersion":1,"idempotencyKey":"availability-001","available":true,"slots":[{"weekday":1,"startMinute":540,"endMinute":720}]}
```

Slots are Malaysian local weekly intervals: Monday is 1, Sunday is 7, minutes range from 0 to 1440. Start is inclusive, end exclusive. Slots must have positive length, integer fields, and no overlap on a weekday; adjacent slots are allowed. The server sorts them. An empty list means no assignable hours. Only `available` and `availabilitySlots` change; approval, tier, languages, gender and allowed tasks remain backend owned. `data.helperProfile` includes `id` and the full profile, with UTC ISO timestamps.

Request example (replace dates with the current activity's exact timestamps):

```json
{
  "contractVersion": 1,
  "idempotencyKey": "request-001",
  "elderId": "elder_demo",
  "activityId": "activity_garden",
  "placeId": "place_garden",
  "startsAt": "2026-10-22T01:00:00.000Z",
  "endsAt": "2026-10-22T02:00:00.000Z",
  "taskType": "walk_with_me",
  "preferredLanguage": "en",
  "preferredHelperGender": "female"
}
```

`activityId` and `placeId` must be explicit IDs or null. Non-activity in-person help has `activityId:null` and a real place. `phone_help` requires both null. Tasks are `walk_with_me`, `sit_with_me`, `phone_help`, `carry_light_item`; language is `bm` or `en`; helper preference is `any`, `female` or `male`.

New bookings must start in the future, end after the start, last at most 24 hours, and use minute-aligned UTC ISO timestamps ending in `Z`. Activity-linked bookings must match an in-person activity's place and entire scheduled interval. Places/activities must belong to the caller's township. A transactional activity/elder lock prevents different keys or family/elder races from creating two active requests for the same attendance. Cancellation releases that lock; verified attendance blocks a new request.

The returned request contains `id`, `townshipId`, `householdId`, `elderId`, `createdBy`, activity/place/time/task/preference fields, `state`, `pairingId`, `helperId`, `elderDisplayName`, `helperDisplay` (`{displayName,tier}` or null), all lifecycle timestamps, `elderConfirmation`/`helperConfirmation` (`{uid,at}` or null), `completionEventId`, `participationIds:{elder,helper}`, `createdAt`, and `updatedAt`. Fields not reached yet are null. Requests contain no wallet balances or claim amounts.

## Assignment and states

```json
{"contractVersion":1,"idempotencyKey":"assign-001","requestId":"ID_FROM_CREATE_RESPONSE","pairingId":"pairing_demo"}
```

Assignment requires an active, mutually accepted recurring pairing for that elder and township; all local booking days must fall within its trial dates and cadence. The helper must be approved, have the task in both their profile and pairing, meet the task tier, match language/gender preferences, and cover the complete interval with current availability. The pilot task tiers are T1 phone help, T2 public walk/sit, T3 carry-light-item. They are permission gates, unrelated to the pending coin policy. Assignment also checks backend-owned blocks and transactionally reserves each Malaysian helper/date document. Overlapping intervals race on those documents; adjacent intervals are allowed. A failure leaves the request and reservations unchanged.

| From | Action | Authorized caller | To |
| --- | --- | --- | --- |
| `requested` | `assignRequest` | Coordinator | `assigned` |
| `assigned` | `accept` | Assigned helper | `accepted` |
| `accepted` | `start` | Assigned helper | `in_progress` |
| `in_progress` | `finish` | Assigned helper | `awaiting_confirmation` |
| `awaiting_confirmation` | `confirm` | Actual elder or assigned helper, only for themselves | Same state until both confirm, then `completed` |
| `requested`, `assigned`, `accepted` | `cancel` | Actual elder, booking-consented family, or coordinator | `cancelled` |

```json
{"contractVersion":1,"idempotencyKey":"accept-001","requestId":"ID_FROM_CREATE_RESPONSE","action":"accept"}
```

There is no reopening, reassignment, or in-progress cancellation in this stage. Neither family nor coordinator may substitute for a participant's confirmation. Confirmation order is unrestricted; a repeat by the same person adds nothing, including with another key. `completedAt` is the server time of final confirmation. Both confirmations and canonical completion writes commit atomically.

Start requires the scheduled start time to have arrived. An activity session must start before activity end and cannot finish before that end. Standalone helping sessions can finish when the helping ends; no invented minimum duration is used. Approval and blocks are rechecked on accept/start. Existing commitments are retained when availability changes. An in-progress helper lock prevents another session starting if an earlier session overruns; finishing releases that lock. Scheduled reservations release on cancellation or final confirmation.

Successful same-key retries return the original saved response after rechecking current role and access, so it may describe an earlier state than the current stream. A changed intent under the same key fails. Family booking consent is checked on every new action and receipt replay, separately from daily sharing consent.

## Completion, progress and pending rewards

Completion creates one canonical event per activity occurrence, or per standalone help request. A participation is identified by that event plus beneficiary UID, independently of command keys. Elders and helpers each have their own participation and claim. An accompanied activity does not create an additional helping-session event for the same attendance. Existing verified attendance, first-verification time and existing claim are preserved. Stage 4 standalone attendance must reuse these identity helpers and the same activity/elder lock.

Activity completion also materializes `activityAttendances` with `mode:companion_session`, `status:verified` and `verificationMethod:mutual_session_confirmation`. No coordinator attendance action is exposed yet. Internal per-participation markers classify activity attendance and standalone walks as `counts`, phone help as `does_not_count`, and standalone sit/carry as `pending_definition`. Future township progress must count elder participations; helper participation is not an extra elder outing. Aggregate/reporting endpoints arrive in Stage 6.

All new reward claims stay `pending_policy`, with `eligible`, `amountCoins`, `rateCoins`, `ruleId`, `ruleVersion` and `ledgerEntryId` null, reason `REWARD_POLICY_PENDING`. No coins, wallet entries, monthly award or four-session threshold are created. Phone-help reward eligibility and exact rates remain undecided. No public award endpoint exists. Reward evaluation/redemption is Stage 5 after policy agreement.

## Read streams for the adapter

All direct browser writes remain denied. Firestore stores `Timestamp`; callable examples use UTC ISO strings. Use IDs returned by the server rather than constructing hashes in Flutter.

| Data/view | Query or document |
| --- | --- |
| Own helper availability | `helperProfiles/{currentUid}` |
| Elder requests | `requests`, `elderId == currentUid`, order `startsAt DESC` |
| Family requests | `requests`, `elderId == selectedElderId`, `householdId == currentHouseholdId`, order `startsAt DESC` |
| Helper assignments | `requests`, `helperId == currentUid`, `townshipId == currentTownshipId`, order `startsAt ASC` |
| Coordinator queue | `requests`, `townshipId == currentTownshipId`, `state == selectedState`, order `startsAt ASC` |
| Family-safe attendance history | `activityAttendances`, `elderId == selectedElderId`, `householdId == currentHouseholdId`, order `verifiedAt DESC` |
| Own participation/claim history | `participations` or `rewardClaims`, `beneficiaryUid == currentUid`, `townshipId == currentTownshipId`, order `verifiedAt DESC` |

An assigned helper reads only their requests. Family request reads require current booking consent; family attendance reads require current sharing consent. Neither grants family financial access. A helper cannot read another participant's claims. Same-township coordinator can read operational records/claims. Backend locks, runtime sessions, canonical events and completion markers remain inaccessible even to coordinator clients. Composite index definitions are included; emulator query tests do not prove production indexes have been deployed.

Watch the household access flags. On consent withdrawal, clear affected family state, unsubscribe immediately and handle denied listeners/reads. An idle request stream is not a consent-change notification: it can retain its last snapshot until another result would be delivered. The client SDK can reuse that synchronized target even for `getDocFromServer()`. An independent server request is denied, command replays fail, and permission is checked again before changed request data is delivered. The backend cannot erase data already retained in frontend memory. Broad unscoped collection queries fail; rules do not filter them into safe results.

## Errors

Use Firebase callable `code` and `details.reason`, not fallback message parsing.

| Code | Relevant reasons |
| --- | --- |
| `unauthenticated` | `AUTH_REQUIRED` |
| `permission-denied` | `PROFILE_REQUIRED`, `ROLE_NOT_ALLOWED`, `TOWNSHIP_NOT_ALLOWED`, `UNRELATED_HOUSEHOLD`, `CONSENT_REQUIRED`, `ELDER_ACCESS_DENIED`, `NOT_ASSIGNED_HELPER` |
| `invalid-argument` | `UNSUPPORTED_CONTRACT_VERSION`, `INVALID_PAYLOAD`, `UNKNOWN_FIELD`, `INVALID_IDEMPOTENCY_KEY`, `INVALID_ID`, `INVALID_AVAILABILITY`, `INVALID_TIME_RANGE`, `INVALID_TASK`, `INVALID_PREFERENCES`, `INVALID_PLACE`, `ACTIVITY_SCHEDULE_MISMATCH`, `INVALID_ACTION` |
| `not-found` | `REQUEST_NOT_FOUND`, `PLACE_NOT_FOUND`, `ACTIVITY_NOT_FOUND` |
| `failed-precondition` | `ELDER_HOUSEHOLD_REQUIRED`, `HELPER_PROFILE_REQUIRED`, `INVALID_TRANSITION`, `PAIRING_NOT_ELIGIBLE`, `HELPER_UNAVAILABLE`, `HELPER_BLOCKED`, `HELPER_BUSY`, `SESSION_ALREADY_DUE`, `SESSION_NOT_STARTED`, `ACTIVITY_NOT_FINISHED`, `ACTIVITY_ALREADY_FINISHED`, `ACTIVITY_REQUEST_EXISTS`, `ACTIVITY_ALREADY_COMPLETED`, `ATTENDANCE_ALREADY_REVIEWED` |
| `already-exists` | `IDEMPOTENCY_KEY_REUSED` |

## Verification and handover routine

1. Stop an existing emulator suite before running `npm.cmd test`. It builds TypeScript, runs unit checks, and starts/stops its own Auth/Firestore/Functions test suite. Tests cover real authenticated callables and scoped reads, consent revocation, atomic conflict handling, timing boundaries with internal test clocks, canonical completion/retries, no coin mutation, JSON response agreement, and selective reset. Flutter end-to-end integration and deployed services are not verified here.
2. Start development emulators with `npm.cmd run emulators`. In a second terminal run `npm.cmd run demo:reset`. Use separate signed-in sessions for elder, family, helper and coordinator. If using the Flutter preview, choose port 8090; Firestore uses 8080.
3. For an immediate lifecycle walkthrough, query `request_demo_ready`, a synthetic **assigned phone-help** request scheduled just before reset. Helper accepts, starts and finishes; helper and elder confirm separately. It finishes without waiting for a future activity and produces no outing or coin credit. This assigned state is explicitly seeded, not created by a production backdating endpoint. The demo helper has synthetic full-day availability/cadence. New activity requests use tomorrow's seeded occurrence and follow actual timing checks.
4. Reset clears requests for the two known demo elders, their attendance/locks, their session-derived participations/claims/markers, known Stage 1–3 receipts and owned reservation slots, plus prior check-in history and named fixtures. It restores accounts/settings/catalogs/zero wallets. Unrelated requests, reservation slots and participants remain; shared completion events stay while another participant exists. This is an offline demo reset, not a concurrent production cleanup API. Seed alone upserts snapshots; use reset for a clean walkthrough.
5. **Commit Stage 3, push `backend-companion-sessions`, create a PR into `main`, then send Developer A the PR link plus this guide and JSON fixtures.** Stage 2 is an ancestor of this branch; if its PR is still open, merging that first keeps the Stage 3 diff easier to review. Give A the branch link before asking them to test its functions.
6. Jointly smoke-test availability -> elder/family request -> coordinator assignment -> helper lifecycle -> both confirmations -> permitted history. Send exact callable name, `code` and `details.reason` for failures. Missing later-stage endpoints remain expected.
7. Continue Stage 4: standalone activity attendance submission and coordinator verification using the same canonical participation identities. Finalize reward amounts/eligibility before Stage 5. Tanya Dulu remains future work.

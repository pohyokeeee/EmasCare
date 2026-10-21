# Backend Stage 2: check-ins and consent

Branch: `backend-checkins-consent`, based on the integrated Stage 1 backend and Phase 1 Flutter preview. This stage implements the agreed v1 check-in/settings interface. Developer A still owns all Flutter UI, models and the repository adapter, including coordinator UI. The checked-in Flutter preview is still a mock; backend verification does not mean its buttons are connected yet.

## What Developer A can connect

Use the [Stage 1 connection settings and demo accounts](BACKEND_FOUNDATION.md). Project `demo-emascare`, region `asia-southeast1`, Auth `127.0.0.1:9099`, Firestore `127.0.0.1:8080`, Functions `127.0.0.1:5001`. Initialize emulator connections before using Firebase SDKs.

| Callable | Signed-in caller | Business fields | Exact `data` result |
| --- | --- | --- | --- |
| `saveElderSettings` | Actual elder, for themselves | `familySharingEnabled`, `familyBookingEnabled`, `dueLocalTime`, `graceMinutes`, `pauseToday` | `{settings}` |
| `submitCheckIn` | Actual elder, for themselves | None | `{checkin,dailyStatus}` |
| `recordPhoneResponse` | Same-township coordinator | `elderId` | `{checkin,dailyStatus}` |

Every input includes `contractVersion: 1` and `idempotencyKey`. Every success is `{contractVersion: 1, data: {...}}` after Firebase callable transport unwrapping. Keep one key across retries of the same action; generate a new key for a newly confirmed action, including on a new day. IDs/roles, local dates, submission times and check-in source come from the backend. Unknown fields are rejected.

Copyable complete examples are in [stage2_checkins.json](fixtures/stage2_checkins.json). These are alternative synthetic UI scenarios, not seed instructions. The private full-contract handoff files remain excluded from Git.

Settings input:

```json
{
  "contractVersion": 1,
  "idempotencyKey": "settings-demo-001",
  "familySharingEnabled": true,
  "familyBookingEnabled": true,
  "dueLocalTime": "09:00",
  "graceMinutes": 30,
  "pauseToday": false
}
```

`dueLocalTime` must be a 24-hour `HH:mm` string. `graceMinutes` is an integer from 0 through 1440. All three switches are required booleans. The response is **`data.settings`**, with `id`, the two consent flags, due/grace fields, `pausedOn` (local date or null), `createdAt` and `updatedAt`.

Saya OK input:

```json
{"contractVersion":1,"idempotencyKey":"checkin-demo-001"}
```

Coordinator phone-response input:

```json
{"contractVersion":1,"idempotencyKey":"phone-demo-001","elderId":"elder_solo"}
```

The phone action records an actual coordinator-reported response; it does not make a phone call. Family/helper accounts cannot act as the elder, change consent or record a phone response.

## Rules and subscriptions

Direct client writes remain denied for every role. A uses the callables for mutations and scoped Firestore streams for current truth. Firestore stores `Timestamp`; callable results/fixtures use UTC ISO strings. Record IDs are provided by callable results and queries.

| Reader/data | Query or document |
| --- | --- |
| Elder private settings | `elderSettings/{currentUid}` |
| Household elder display/access flags | `households/{currentHouseholdId}` |
| Elder raw check-in history | `checkins`, `elderId == currentUid`, order `localDate DESC` |
| Linked family-safe history | `dailyStatuses`, `elderId == selectedElderId`, `householdId == currentHouseholdId`, order `localDate DESC` |
| Coordinator exceptions | `checkins`, `townshipId == currentTownshipId`, `localDate == selectedLocalDate`, `state IN [reminded,missed]`, order `dueAt ASC` |

Filter a history result by the Malaysian current date to display today. An empty query means no materialized record yet, not a successful check-in. There is no caller-controlled historical submission endpoint.

Family daily reads always require current sharing consent, including for previously stored records and existing listeners. Booking consent does not grant daily status access. Sharing consent does not grant booking authority. The private `checkins` record is restricted to its elder and same-township coordinator. The family-safe projection contains only `elderId`, `householdId`, `localDate`, `state`, `submittedAt`, `updatedAt` (plus frontend `id`). It excludes `recordedBy`, `source`, due/grace settings, private notes and all finances.

On withdrawal, A must clear already-rendered family data, cancel affected subscriptions and handle `permission-denied`. The backend cannot remove content already held in frontend memory. The integration test checks both a denied new read and revocation of an active Firestore listener. Family cannot read settings, raw check-ins or wallets, even with both permissions enabled.

## Behavior and retries

- Malaysian date boundaries use UTC+08:00. `pauseToday` sets `pausedOn` to today's local date; `false` clears it. Yesterday's pause does not apply today.
- Saving settings atomically updates private settings, both household access flags, today's check-in and its safe status. Other elders' access entries are preserved.
- For an unsubmitted record, before due time is `pending`; from due until grace expiry is `reminded`; at/after grace expiry is `missed`. Zero grace changes directly from pending to missed. A matching pause is `paused`.
- Saving settings refreshes an unsubmitted day's due/grace/state. An already submitted `ok` record retains its first timestamp, actor, source and original due/grace history. Pausing it leaves the response visible as `ok` while settings carry today's pause.
- Paused, unsubmitted days reject app and phone responses with `CHECKIN_PAUSED`. Unpause before submitting. Repeating an already successful response returns that existing response, including if it was later paused.
- The first valid app or coordinator response for an elder/day wins. Retries and different keys cannot replace its timestamp/source or create another daily record. The private record, safe projection and receipt commit together.
- Successful same-key retries return the original response and recheck current role, township and household. A changed payload with the same key fails. Replaying an earlier settings action never reapplies stale consent; its response can be older than the current settings stream. Reusing yesterday's successful key returns yesterday's result, so create a new key for today's new action.
- Late responses update status to `ok` and leave previously stored alert history intact. Stage 2 creates no alert notifications, due-processing scheduler, rewards or progress credits.

States are refreshed when these commands or seed run. Unattended reminders are not implemented. `processDemoDueItems` and its labelled coordinator trigger remain Stage 6 work, including creation of absent-day records and alerts without opening an elder screen. Do not present the initial `reminded/missed` fixture as a delivered notification.

## Errors for A's adapter

Firebase callable errors expose `code` and `details.reason`; localize on the reason rather than parsing fallback text.

| Code | Reasons |
| --- | --- |
| `unauthenticated` | `AUTH_REQUIRED` |
| `permission-denied` | `PROFILE_REQUIRED`, `ROLE_NOT_ALLOWED`, `TOWNSHIP_NOT_ALLOWED`, `UNRELATED_HOUSEHOLD` |
| `invalid-argument` | `UNSUPPORTED_CONTRACT_VERSION`, `UNKNOWN_FIELD`, `INVALID_PAYLOAD`, `INVALID_IDEMPOTENCY_KEY`, `INVALID_SETTINGS`, `INVALID_DUE_TIME`, `INVALID_GRACE_MINUTES`, `INVALID_ID` |
| `failed-precondition` | `CHECKIN_PAUSED`, `SETTINGS_NOT_CONFIGURED`, `ELDER_REQUIRED`, `ELDER_HOUSEHOLD_REQUIRED` |
| `already-exists` | `IDEMPOTENCY_KEY_REUSED` |

## Local verification routine

From the repository root, first stop any existing emulator suite that occupies its ports. Run:

```powershell
npm.cmd test
npm.cmd run emulators
```

`npm.cmd test` builds, runs unit checks, and starts/stops its own test suite. While the separately started development emulators remain running, use a second terminal:

```powershell
npm.cmd run demo:reset
```

Reset remains local-only and refuses conflicting project/emulator settings. It clears all check-in/daily-status dates for `elder_demo` and `elder_solo`, clears the known demo actors' implemented-stage receipts, and restores the six demo accounts/settings/catalogs/zero wallets. Stage 3 adds selective companion cleanup; see [its reset scope](BACKEND_SESSIONS.md). Other elders' records and unimplemented-domain command receipts are preserved. Seed alone upserts today's fixture snapshot; use reset for an entire fresh walkthrough.

The standalone elder has a local-midnight, zero-grace overdue fixture so the coordinator can exercise `recordPhoneResponse`. It is synthetic, not a live missed alert. Both elders have today's safe status, with sharing disabled for the standalone elder.

The Flutter preview defaults to 8080, which conflicts with Firestore. Use a third terminal if previewing the app alongside the backend:

```powershell
app/preview.ps1 -Port 8090
```

Then open `http://127.0.0.1:8090`. This changes no Flutter files and does not connect the current mock repository to Firebase; that adapter work belongs to Developer A.

## Handover after Stage 2

1. After backend checks pass, commit the stage changes, push `backend-checkins-consent` and open a pull request into `main`. Send Developer A the PR/branch link so they can fetch the implementation before starting integration.
2. Send Developer A this guide and the Stage 2 JSON fixtures. They can connect the three callables and safe-status stream using their own Flutter adapter.
3. Jointly verify elder sign-in -> Saya OK -> permitted family update -> withdrawal denies family -> coordinator records the separate elder's phone response. Use distinct authenticated sessions/accounts. No cloud service has been provisioned or deployed by this stage.
4. Continue Stage 3: helper availability, companion requests, accepted-pair assignment, reservation conflicts and two-person session completion. Reward rates remain pending and no check-in earns coins.

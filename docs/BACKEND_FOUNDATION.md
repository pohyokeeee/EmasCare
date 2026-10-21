# Backend Stage 1

Stage 1 establishes the local Firebase backend on branch `backend-foundation`. Developer A owns **all Flutter files**, including coordinator UI, navigation, models and the repository adapter. Developer B owns TypeScript Functions, Auth/data, permissions, rules/indexes, scripts and backend checks.

Stage 2 adds working check-in/settings commands, current daily fixtures and scoped check-in history. Read [the Stage 2 handover](BACKEND_CHECKINS.md) for the current callable examples, reset coverage and integration steps.

The agreed API contract is v1, document revision 2, shared separately. Its local Markdown and JSON files remain excluded from Git. This guide covers the implemented foundation; domain functions in that contract arrive in subsequent stages.

## Start locally

Install a system Node.js 22 or 24 with npm, plus a Java JDK (21 or newer recommended for current emulator tooling). This checkout was verified with system Node 24.14.0, npm 11.9.0 and Java 25. The project installs a pinned local Node 22.23.3 runtime; npm scripts use it for Functions and verification. An initial npm engine warning under system Node 24 refers to the Functions target of Node 22.

From the repository root:

```powershell
npm.cmd ci
npm.cmd test
npm.cmd run emulators
```

On macOS/Linux use `npm` in place of `npm.cmd`. First installation and emulator startup need internet access for packages and emulator binaries. No Firebase login, real project, service account, billing or API key is required for this local foundation. Leave the emulator terminal running. On Windows the launcher resolves the actual JDK directory (or uses `JAVA_HOME`) so Oracle's Java redirector does not leave an orphaned emulator on shutdown; it changes no global Java/PATH settings.

In a second terminal at the repository root:

```powershell
npm.cmd run demo:seed
```

Open <http://127.0.0.1:4000> to inspect Auth and Firestore. Stop the suite with Ctrl+C in its terminal. Data is in memory: restart and seed again to restore the foundation fixtures.

## Connection details to send Developer A

| Setting | Value |
| --- | --- |
| Firebase project ID | `demo-emascare` |
| Callable region | `asia-southeast1` |
| Authentication | `127.0.0.1:9099` |
| Firestore | `127.0.0.1:8080` |
| Functions | `127.0.0.1:5001` |
| Emulator UI | `http://127.0.0.1:4000` |
| Local Firebase API key | `local-demo-key` (placeholder for Auth emulator only) |
| Local app ID | `1:1234567890:web:emascare-demo` (placeholder) |
| Local sender ID | `1234567890` (placeholder) |
| Local auth domain, if needed | `demo-emascare.firebaseapp.com` (placeholder) |

A initializes Firebase with the demo project and connects Auth, Firestore and Functions to these emulators **before** issuing SDK operations. Functions must use the listed region. These are local browser values, not cloud project configuration. Both developers can run the same backend on their own computers. `127.0.0.1` refers to the computer running the browser; accessing another computer's emulator or a physical phone is outside this setup.

All accounts use **`EmasCare-local-2026!`**, an emulator-only password:

| Role/scenario | Email | Auth UID |
| --- | --- | --- |
| Elder | `elder@emascare.test` | `elder_demo` |
| Family | `family@emascare.test` | `family_demo` |
| Helper | `helper@emascare.test` | `helper_demo` |
| Coordinator | `coordinator@emascare.test` | `coordinator_demo` |
| Standalone elder | `solo@emascare.test` | `elder_solo` |
| Unrelated family | `unrelated@emascare.test` | `family_unrelated` |

Sign in with Firebase Auth email/password. Read `users/{currentUid}` for the server-owned role, township and household. Do not infer a role from the email or an account switcher. A newly self-registered Auth user has no authorized app profile.

## Implemented callable and sample

`getBackendContext` is a read-only foundation diagnostic for signed-in users with a valid server profile. It returns only the current user's profile and does not require an idempotency key. It supplements the separately agreed domain contract for connection testing; no production UI flow needs to depend on it.

Input after signing in as the elder:

```json
{"contractVersion":1}
```

Application result after Firebase's callable transport is unwrapped:

```json
{
  "contractVersion": 1,
  "data": {
    "profile": {
      "uid": "elder_demo",
      "displayName": "Demo Elder",
      "role": "elder",
      "townshipId": "township_demo",
      "householdId": "household_demo",
      "locale": "en"
    }
  }
}
```

Errors use Firebase `HttpsError`, with a stable `details.reason`. Foundation reasons include `AUTH_REQUIRED`, `PROFILE_REQUIRED`, `ROLE_NOT_ALLOWED`, `TOWNSHIP_NOT_ALLOWED`, `UNRELATED_HOUSEHOLD`, `CONSENT_REQUIRED`, `UNSUPPORTED_CONTRACT_VERSION`, `UNKNOWN_FIELD` and `IDEMPOTENCY_KEY_REUSED`.

An additional `foundationProbe` callable exists **only in the Functions emulator** for backend tests. It exercises scoped authorization and transactional receipts using isolated probe records. Do not wire it into app UI. It is absent from non-emulator exports, has no reward behavior, and never alters domain records or wallets.

## Seeded records and permitted reads

`scripts/fixtures.mjs` is the executable seed source. It does not import the ignored UI fixture bundle, whose scenarios are alternatives and include a hypothetical redemption balance.

The seed contains six actual Auth accounts and corresponding profiles, four households, separate elder settings, one approved helper with availability, one accepted recurring trial pair, two upcoming dated activities, two illustrative places (one warning), one 100-coin **mock** voucher and three zero-balance wallets. Stage 2 also seeds current check-ins and safe daily statuses for both elders; the standalone elder has an overdue fixture for coordinator phone follow-up. Dates are generated from the seed execution time. The standalone elder has no companion pairing. No completed participation, reward rate, credited history or positive wallet balance is fabricated.

Rules currently permit:

- Current user's profile/household; same-township coordinator profile/household reads.
- Township activities, places and voucher catalog.
- Elder's own private settings; same-township coordinator access. Family cannot read private settings.
- Helper's own profile; same-township coordinator access. Residents cannot read individual helper availability.
- Pairings for their elder/helper and same-township coordinator.
- Elder's own wallet and helper's own wallet/ledger; same-township coordinator audit. Family has no financial access.
- Family-safe daily status reads for a linked family with **current sharing consent**. Stage 2 creates these statuses and permits raw check-in history only to its elder and same-township coordinator.

All direct client writes are denied, including for coordinators. Commands must perform protected writes. Receipts, probes and all remaining collections are denied to clients until their stage adds explicit read policies. Helpers and family do not gain additional permissions through token role claims.

Queries must match the rules; rules do not filter an unrestricted collection. A uses:

| Collection | Constraints |
| --- | --- |
| `activities` | `townshipId == currentProfile.townshipId`, order `startsAt ASC` |
| `places`, `voucherCatalog` | `townshipId == currentProfile.townshipId` |
| `users` | Own document; coordinator lists constrained by `townshipId` |
| `households` | Own household document; coordinator lists constrained by `townshipId` |
| `helperProfiles` | Own UID document; coordinator can fetch known same-township helper IDs |
| `pairings` | Own `elderId` or `helperId`; coordinator uses `townshipId` and optionally `active` |
| `wallets`, nested `entries` | Own wallet document/entries; coordinator audit scoped by `townshipId` |
| `dailyStatuses` | `elderId == selectedElderId`, `householdId == currentHouseholdId`, order `localDate DESC` |

The compound indexes match the activity, coordinator pairing, family daily-history and Stage 2 check-in-history/exception queries. Later stages add indexes with their actual queries. The emulator verifies rules/query authorization, but does not prove production index readiness; deployed indexes must later be checked on the real project.

## Retry and permission helpers

`functions/src/auth.ts` reads the current server-owned profile, enforces roles/township and checks family relationship plus separate sharing/booking consent from private settings. Mutation authorization runs inside the Firestore transaction.

`functions/src/commands.ts` scopes a receipt to actor UID + function name + caller idempotency key and hashes the canonical business payload. A successful retry returns the stored original result. Reusing the key with a changed payload fails. Every replay first rechecks current profile, relationship and consent. Effects and the receipt commit together; exceptions commit neither. Transaction callbacks must read before writing and may run multiple times, so no external side effects belong inside them.

This protects command retries. Later reward logic additionally needs canonical event/participant identity so two different requests or keys cannot reward the same participation twice. No reward endpoint or financial mutation is implemented in Stage 1. `saveElderSettings` will return `data.settings`; `setHelperAvailability` will return `data.helperProfile` as agreed.

## Reset and verification

With emulators running:

```powershell
npm.cmd run demo:reset
npm.cmd run demo:smoke
```

Reset deletes/recreates the explicit fixture documents/accounts, removes known demo elders' check-ins/daily statuses across dates, and clears known demo actors' implemented-stage receipts. Stage 3 adds selective request, reservation and completion cleanup; Stage 4 includes standalone attendance. See [the current reset scope and walkthrough](BACKEND_ATTENDANCE.md). Other elders' records, unrelated Auth accounts and unimplemented-domain receipts remain. This is a scoped demo reset. Never use it to repair real financial history; expand cleanup deliberately as later stages introduce demo-owned data. Seed alone upserts the current fixture snapshot and restores its default settings/balances; use reset before repeating an entire walkthrough.

Both scripts validate the exact demo project and loopback emulator hosts before Admin client initialization. Existing conflicting project or host environment variables cause failure. They cannot target a live Firebase project.

`npm.cmd test` builds TypeScript, runs unit checks, starts an isolated local emulator suite, executes callable/Auth and Firestore-rules tests, then stops it. Stop an already running suite first to free the ports. `demo:smoke` also resets the known foundation fixtures; run it on local demo data only.

Coverage includes real email/password sign-in, callable envelopes, missing/forged role failures, cross-township denial, current consent and receipt replay, concurrent duplicate submission, changed-key-payload rejection, transaction rollback, client write denial, financial privacy, query scope, reset CLI behavior and preservation of unrelated data. Expected `PERMISSION_DENIED` log lines during rules tests are passing negative cases.

The installed backend runtime dependencies have no advisories in `npm audit --omit=dev` at verification time. A full audit also includes Firebase CLI/test SDK dependencies and currently reports upstream development-tool advisories; no forced major dependency downgrades or overrides were applied.

## Outstanding external setup

The current mode is local only. No real Firebase project access, billing, cloud deployment or Hosting release has been established. A real project, Auth provider enablement, database location, deployment permissions, secrets and hosted-origin checks belong to the later release setup.

No Gemini API key was available in the checked environment and no presentation-browser audio sample was supplied. A real audio/model/MIME feasibility call therefore remains unverified; Stage 1 does not claim the plan's full voice checkpoint. Before voice implementation, Developer B needs a server-held credential and Developer A's actual short BM/EN recording plus MIME type. Never send the key in Git or Flutter. Manual booking remains the planned fallback. Reward rates/eligibility and sit/carry outing classification remain pending separately.

## Next actions and stages

After Stage 1, the project owner should:

1. Run the start and seed commands above and inspect the six accounts in the emulator UI.
2. After backend checks pass, commit the stage changes, push the branch and open a pull request into `main`. Send Developer A the PR/branch link so they can fetch the implementation.
3. Send Developer A this guide's connection details, accounts and `getBackendContext` example. They can independently verify Auth and catalog streams without waiting for domain features. Keep the private contract files excluded from Git; review the pull request before merging. Cloud deployment is a later step.
4. Continue Stage 2: settings/check-ins, separate consent, permitted family updates and coordinator phone responses. Its acceptance check is an elder check-in that persists and becomes unreadable to family when sharing is withdrawn.

The remaining backend sequence is:

| Stage | Work | Check before moving on |
| --- | --- | --- |
| 2 | Check-ins, consent, family status | Cross-account persistence and immediate consent withdrawal |
| 3 | Availability, requests, assignment, reservations, session lifecycle | Compatible assignment, no reservation races, two distinct confirmations |
| 4 | Standalone attendance, canonical events/participants | Coordinator verification; activity/session evidence resolves to one participant |
| 5 | Approved rewards, both-role wallets/ledger and mock redemption | Once per eligible participation, atomic debit, owner-only access; no guessed rates |
| 6 | Voice, reports/block, warnings, due processing, cheers and summaries | Authorized operations, actual audio feasibility and suppressed small cohorts |
| 7 | Flutter integration, release setup and rehearsal | Focused checks, two reset-based rehearsals and explicit deployed/demo limitations |

At each stage handover, report what works, checks/gaps, what Developer A can connect, the project owner's next action, and the next stage. Keep all Flutter changes with Developer A.

## References

- [Firebase Functions runtime configuration](https://firebase.google.com/docs/functions/manage-functions)
- [Firebase demo projects and Auth emulation](https://firebase.google.com/docs/emulator-suite/connect_auth)
- [Firestore rules testing](https://firebase.google.com/docs/rules/unit-tests)

# Copyable prompt for Developer A

Send this prompt to your teammate together with the Stage 6 guide and JSON fixtures. The API rehearsal is backend evidence; it does not mean the Flutter screens are connected.

```text
I am Developer A for EmasCare. Stage 6 backend PR #13 is merged into main.
I own all Flutter UI, including coordinator screens, shared Dart models,
navigation and Firebase repository adapters. Developer B owns the backend.

Read README.md, docs/BACKEND_COORDINATION.md,
docs/fixtures/stage6_coordination.json and docs/INTEGRATION_REHEARSAL.md.
Use docs/PROTOTYPE_PLAN_2_DAYS.md as the current implementation plan.
Keep the working Stage 1-5 check-in/session/attendance/wallet integration.
Tanya Dulu remains outside the build.

Create a frontend Stage 6 integration branch from current main. Implement:
- submitReport and coordinator reviewReport (new -> seen -> done).
- setPlaceWarning and explicit clearing. Expiry means needs review, not safe.
- blockHelper for actual elders/coordinators, with family denial and errors.
- processDemoDueItems as an explicitly operator-run demo action.
- Scoped notifications and markNotificationRead.
- sendFamilyCheer using a verified outing's participationId, once per family.
- getProgress for permitted elder/helper/household/township scopes.
- getAvailabilitySummary with synthetic/suppressed labels and no schedules.
- getCoordinatorSummary for the coordinator dashboard.
- parseVoiceBooking with typed/manual fallback, clarification, readback and
  explicit confirmation through existing createRequest. Do not auto-book.

All callable results unwrap to {contractVersion:1,data:{...}}.
Existing saveElderSettings returns data.settings.
Existing setHelperAvailability returns data.helperProfile.
New exact result shapes and JSON examples are in the Stage 6 guide/fixtures.
Use current Auth identity and stable per-action idempotency keys on retries.
Never write domain records, balances or roles directly from Flutter.

Sharing consent and booking consent are separate. On revocation, cancel/reset
related listeners and hide old protected data. Query notifications by the
current recipientUid, selected elderId and consentScope, sorted by createdAt.
Do not use a broad family notification/financial query.

Rewards remain the owner-approved 20 coins per verified participation for
each actual elder/helper beneficiary. The voucher costs 100 coins. Phone
help earns under that policy but does not count as an outing; standalone
sit/carry outing classification remains pending. Display unknown/pending
states accurately, and preserve the existing wallet/redemption retry flow.

For local integration, have Developer B run the emulators, demo:prepare and
demo:check. demo:rehearse is a repeatable API walkthrough that leaves real
demo histories/coins/vouchers for inspection. It uses explicit uncompleted
assigned fixtures; also test new booking and coordinator assignment in UI.
On separate computers, each laptop runs its own local demo backend; these
loopback emulator addresses do not connect to the other person's laptop.
For a fresh hands-on UI lifecycle test, prepare/check a fresh demo and skip
the API rehearsal until after the UI has completed those session fixtures.

No Gemini key/model is configured by default. Show recoverable parser errors
and keep manual booking available. Do not present fixtures as live inference.
Audio is at most 30 seconds and 1 MiB decoded, using the documented container
MIME labels. Keys remain server-side; live BM/EN device audio is a separate
test after configuration.

Preserve BM/EN, narrow layouts and accessibility settings. Run appropriate
Flutter tests/analyzer and a connected browser walkthrough. Record actual
passes and gaps in a frontend verification document; do not claim completion
from fixtures or backend API tests alone. Do not deploy cloud services or
change backend business logic/configuration without coordinating with B.
```

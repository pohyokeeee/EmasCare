# EmasCare

A community companionship app for older residents of a township. Elders check in daily, book outings and neighbourly company, and earn small rewards for taking part. Families see only what the elder consents to share. Helpers and coordinators run the sessions.

> **Status:** MVP prototype running locally on Firebase emulators (`demo-emascare`). No cloud services are deployed.

## Features

### For elders
- **Saya OK:** one button to say "I'm fine today". The elder sets a due time and a grace period, and can pause a day. If a check-in is missed, the coordinator sees it as an exception.
- **Jom Keluar (activities and outings):** a list of upcoming community activities. Each shows the place's access details (step-free access, toilet, seating, walking time, notes) and a Maps link. Residents can filter for step-free places, and a warning shows if a place has a problem or is closed.
- **Minta Teman (companion booking):** the elder asks for a companion for a walk, sitting together, carrying light items, or phone help. They choose a date, time and meeting place, review the request, then confirm.
- **Voice and text booking:** the elder describes the request in words and the app prepares a draft to read back before they confirm. If the AI provider is switched off, the app says so and offers the normal booking form.
- **My rewards:** a wallet of coins earned from verified activities and sessions, with a history of credits and a mock voucher the elder can redeem.
- **Consent controls:** sharing consent lets linked family see the permitted daily status, progress and session history. Companion requests are created only by the elder; family has no booking or session-mutation controls.

### For family
- **Daily status:** see whether the elder checked in, but only while the elder has allowed sharing. Turning sharing off clears it straight away.
- **Session visibility:** see the elder's permitted session status and history while sharing consent is on. Family cannot create, cancel, assign or confirm a session.
- **Community availability:** check in or out when free to be contacted. This is an informational availability signal, not a booking or helper assignment.
- **Progress and cheers:** see the elder's outings and send a cheer. A cheer doesn't earn coins.

### For helpers (neighbour companions)
- **Availability:** set the weekly times they can help.
- **Assigned sessions:** see only the sessions assigned to them. They accept, start and finish each one, then confirm.
- **Session chat:** chat with the assigned elder after assignment, including follow-up after completion.
- **My rewards:** the same wallet and mock voucher as elders.

### For coordinators
- **Assign requests:** match a request to a permitted, available helper.
- **Verify attendance:** approve or reject activity attendance submitted by elders.
- **Place warnings:** set a warning with an expiry. It stays visible as "needs review" after it expires until a coordinator clears it.
- **Reports and blocking:** review place problems and helper reports, and block a helper from an elder.
- **Check-in exceptions:** process due check-ins and record a phone response. This records a reported response and doesn't place a call.

### How rules and rewards work
- A two-person session only completes after **both** the elder and the helper confirm. One confirmation alone earns nothing.
- Each eligible verified activity or session creates a monthly reward claim for **20 coins for each actual participant**, once, even if the action is retried. Claims release on the first day of the next Malaysia-time calendar month through a coordinator settlement; five released credits pay for the 100-coin **mock voucher**. There is no real shop or payment.
- Check-ins, cheers and cancelled or half-confirmed sessions earn no coins.
- Each role only sees its own data. An unrelated family account sees nothing about other households.

### Also included
- **Languages and accessibility:** English and Bahasa Malaysia, larger text, gentler motion and solid navigation.
- **Design preview:** a sample-data mode, reached from the sign-in page, for looking around without the backend.

## Setup (Windows)

You do this once. After that, starting the app is one command.

**1. Install three things**
- **Flutter** (the app toolkit).
- **Java (JDK 21 or newer)**, which the local database needs.
- **Node.js.** The repository includes the version it needs, so you usually don't install it yourself.

**2. Get the code and install packages.** In PowerShell:

```powershell
git clone https://github.com/pohyokeeee/EmasCare.git
cd EmasCare
npm.cmd ci
```

**3. Start everything**

```powershell
.\app\demo.ps1
```

The first run builds the app and starts a local test backend, so it takes a few minutes. Wait for the word **Ready**.

**4. Open the app** at http://127.0.0.1:8090 and sign in with a demo account from the table below.

**5. When you're done**

```powershell
.\app\demo.ps1 -Mode backup   # save your changes
.\app\demo.ps1 -Mode stop
```

Notes:
- Everything runs on your own computer with fake test data. Nothing is sent to the cloud.
- If port 8090 is already in use, add `-Port 8091` to each command and open that address.
- Don't run `npm run demo:reset` unless you want to erase the saved demo history.
- If something fails, check `.cache/ui-demo/backend.err.log`.
- Other launcher commands: `.\app\demo.ps1 -Mode status`, and `-SkipBuild` when the existing web build is current.

## Demo accounts

All use the emulator-only password `EmasCare-local-2026!`.

| Role | Email |
| --- | --- |
| Elder | elder@emascare.test |
| Family | family@emascare.test |
| Helper | helper@emascare.test |
| Coordinator | coordinator@emascare.test |
| Standalone elder | solo@emascare.test |
| Unrelated family | unrelated@emascare.test |

Open each role in its own new tab. "Explore the design preview" on the sign-in page is a separate sample-data mode.

## Testing

```powershell
.\app\preview.ps1 -Mode check   # analyze + Flutter + browser/launcher tests
.\app\preview.ps1 -Mode build   # release web build
npm.cmd run test:unit           # backend unit tests
npm.cmd run demo:check          # read-only integration checks
```

## Repository layout

```text
app/         Flutter Web app (developer A)
functions/   Cloud Functions in TypeScript (developer B)
docs/        Plans, backend stage guides, fixtures
scripts/     Seed, reset, reward and integration scripts
tests/       Backend and rules tests
```

## Documentation

- **Run and demo:** [Final demo guide](app/FINAL_DEMO_GUIDE.md) · [Local backend setup](app/LOCAL_BACKEND.md) · [Final verification record](app/FINAL_VERIFICATION.md)
- **Plans:** [Current plan](docs/PROTOTYPE_PLAN_2_DAYS.md) · [Product plan](Township%20%28SimeDarby%29%20Hackathon%202026.md) · [Original 3-day plan (reference)](docs/FULL_IMPLEMENTATION_PLAN_3_DAYS.md)
- **Backend stages:** [1 Foundation](docs/BACKEND_FOUNDATION.md) · [2 Check-ins](docs/BACKEND_CHECKINS.md) · [3 Sessions](docs/BACKEND_SESSIONS.md) · [4 Attendance](docs/BACKEND_ATTENDANCE.md) · [5 Wallet](docs/BACKEND_WALLET.md) · [6 Coordination](docs/BACKEND_COORDINATION.md) · [Integration rehearsal](docs/INTEGRATION_REHEARSAL.md)
- **Frontend verification by phase:** [Stage 3](app/STAGE3_VERIFICATION.md) · [Stage 4](app/STAGE4_VERIFICATION.md) · [Phase 5](app/PHASE5_VERIFICATION.md) · [Stage 6](app/STAGE6_VERIFICATION.md)

## Scope and decisions

- **Out of scope for the MVP:** Tanya Dulu (future), cloud deployment, push delivery, automatic scheduling, and live Gemini/microphone audio.
- **Rewards (current):** 20-coin monthly claims for each actual participant per verified session, released after the next MYT month boundary. This replaces the earlier fixed monthly award and role-rate designs.
- **Ownership:** developer A owns all Flutter code, and developer B owns the backend.

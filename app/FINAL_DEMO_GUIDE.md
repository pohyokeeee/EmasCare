# Final MVP demo guide

## Start and preserve the demo

From a PowerShell terminal in the repository root:

```powershell
.\app\demo.ps1
```

Open http://127.0.0.1:8090 after **Ready** appears. Initial prerequisites: installed Flutter, JDK 21+, and `npm.cmd ci` in the repository root. Do not reinstall dependencies while the emulators hold native modules open. The launcher uses the repository's Node 22, finds a supported JDK, builds Functions and Flutter, and starts only local `demo-emascare` services. Internet is needed for the Firebase browser SDK on first load.

```powershell
.\app\demo.ps1 -Mode status
.\app\demo.ps1 -Mode backup
.\app\demo.ps1 -Mode stop
.\app\demo.ps1 -SkipBuild # Only when the existing web build is current
```

Start reuses compatible running services. A newly started backend imports the last successful launcher backup, then prepares accounts, approved reward configuration and uncompleted practice assignments without completing sessions or inventing balances. Reusing an existing backend performs read-only readiness checks. Stop first backs up a launcher-owned backend, then stops only processes whose identities match the launcher records. Reused services remain running. Backup failure leaves the backend running. An unexpected computer shutdown can lose changes since the last backup, so back up after a rehearsal.

Exports and process logs are under `.cache/ui-demo/`; they contain private emulator account data and must stay out of Git. Keep the latest export and pointer together. Never run `demo:reset` to fix a startup problem when retaining demo history.

If 8090 belongs to another app, use `-Port 8091` consistently for start/status/stop and open that address. Firestore occupies 8080. If a service fails, read `.cache/ui-demo/backend.err.log` and `backend.log`; retry after correcting the cause. Do not delete a live launcher lock. After source edits, run without `-SkipBuild` and refresh the browser. After a backend restart, sign in again if the previous session is no longer valid.

## Accounts

Each account below uses emulator-only password `EmasCare-local-2026!`.

| Role | Email |
| --- | --- |
| Elder | elder@emascare.test |
| Family | family@emascare.test |
| Helper | helper@emascare.test |
| Coordinator | coordinator@emascare.test |
| Standalone elder | solo@emascare.test |
| Unrelated family | unrelated@emascare.test |

Use separate newly opened tabs for each role; duplicated tabs may copy sign-in state. The Account screen signs out. Server profiles determine roles; changing the URL does not grant access. **Explore the design preview** is a separate fixture-only experience.

## Connected walkthrough

1. Elder: press **Saya OK**. Family: observe the permitted daily status. Refresh both tabs and verify the saved result.
2. Elder: turn sharing off and save. Family must clear the affected status/progress. Booking consent is separate: leave it on and verify booking access remains available. Restore sharing for the following demo. Pause today, save and refresh; then unpause and save.
3. Elder: open **My companion**, create a new request with a future MYT date/time, task, duration and a valid meeting place for physical help. Review before confirming. Phone help needs no place. Keep the request time visible for matching it across tabs.
4. Coordinator: find the requested item and assign the permitted helper. Helper: accept it, start at or after its scheduled start, then finish. Activity-backed sessions also enforce the activity end time. Prepared assignments can demonstrate these transitions, but do not demonstrate request creation or assignment.
5. Elder and helper: confirm their own participation separately. The first confirmation alone must not complete a two-person session or award coins. After both confirmations, verify one **20-coin** credit for each actual participant. Refresh to verify persistence. A retry must not create another credit. Phone help earns coins but is excluded from outing goals.
6. Repeat genuine verified participation until the wallet has at least **100 coins**. Open **My rewards**, review and confirm the demo voucher. Check the saved receipt and the 100-coin debit after refresh. These are mock vouchers with no merchant fulfilment. Do not add opening balances to shortcut this demo.
7. Family: inspect permitted progress and send a cheer for the elder's latest eligible outing. Coordinator: use **Tools**, inspect check-in exceptions, explicitly process due check-ins, and record a phone response. The latter records a reported response; it does not place a call. In-app updates are saved records, not push delivery.
8. Open a place/report or blocking review. Confirm that the exact place/session/participants and MYT review deadline are understandable before submitting. Cancel a blocking review during a normal rehearsal to preserve the active companion pair; blocked pairs have no MVP unblock action.
9. Teman: try the parser with the local provider disabled and use manual booking when unavailable. Microphone recording requires deliberate permission and remains a separate device check. Live Gemini/audio is not part of this verification without provider configuration.
10. Switch BM/EN, try Larger text, Gentler motion and Solid navigation, and inspect phone/desktop layouts. Test unrelated-family access and verify no other household status, progress or wallet is displayed.

## Developer checks

```powershell
.\app\preview.ps1 -Mode check
.\app\preview.ps1 -Mode build
.\node_modules\node\bin\node.exe scripts/check-integration.mjs
```

The first command runs analyzer, Flutter tests and browser/startup/voice/launcher tests. The last command is read-only against the running demo: authenticated roles, wallet/ledger consistency, scoped denials, progress and configured reward policy. It does not replace the browser walkthrough. Historical stage verification files describe their original runs; consult the final verification record for the current pass/gap evidence.

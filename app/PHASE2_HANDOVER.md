# Phase 2 UI handover

Branch: `ui-phase-2`, from merged main `a751ee9`. The owner approved building the UI while Developer B finishes Stage 3, then authorized committing, pushing and merging through a pull request on 21 October 2026.

## Delivered

- Activity catalogue with Malaysia dates, this-week/step-free filters, responsive cards and activity details.
- Place accessibility, unknown/missing detail states, walking time, notes, expiring notices and validated HTTPS Google Maps links. Fixture conditions are explicitly illustrative.
- Elder/family request form and review: task, date/time, duration, language, meeting place and optional notes. Family booking consent is independent of daily sharing.
- Companion summaries, helper availability presentation, coordinator assignment sheet, request/session progress, early cancellation and separate participant confirmations.
- BM/EN, keyboard semantics, larger text, reduced motion and solid navigation using the existing warm white/forest green design and spring press feedback.

## Connected versus sample

| Area | Local Firebase mode | Design preview |
| --- | --- | --- |
| Stage 2 authentication/check-ins/consent | Existing saved backend behavior | Existing sample behavior |
| Activities and places | Read-only township-scoped streams | Separate sample catalogue |
| Pairings | Elder/helper own pairing plus township; coordinator active same-township pairings | One accepted sample pairing |
| Helper availability | Helper's own saved profile, read-only | Availability switch controls sample assignment |
| Requests and sessions | Reviewable unsent drafts; mutations disabled | In-memory request → assignment → accept → start → finish → both confirm |
| Coins/redemption | Pending | No credits or redemption |

Family never subscribes to private pairings or helper profiles. All connected community state clears on sign-out/profile-scope change/permission failure; affected open sheets also close. Family request drafts react to booking-consent withdrawal. Server-owned roles remain authoritative.

The current rules require **both** `elderId`/`helperId` and `townshipId` equality filters for participant pairing queries. The adapter and read-only verifier include both, extending the Stage 1 guide's owner-only shorthand. No rules or indexes were changed.

Sample requests survive preview-role switches within the tab and disappear on reload/reset. Assignment requires the sample approved pairing and available helper within the displayed 08:00–18:00 MYT sample hours. Helper transitions must run in sequence. A session remains incomplete after one confirmation; family/coordinator cannot confirm for either participant. Sample models have no Stage 3 JSON serializer and do not define B's API.

## Review locally

Keep the existing emulators running. Full first-time setup and accounts are in [LOCAL_BACKEND.md](LOCAL_BACKEND.md). If the preview server is already on 8090, rebuild and reload it:

```powershell
cd 'C:\Users\user\Documents\PROJECTS\EmasCare\app'
.\preview.ps1 -Mode build
# Start only if port 8090 is free:
.\preview.ps1 -Mode serve
```

1. Open `http://127.0.0.1:8090`. Sign in as elder and open Activities. Inspect Garden walk and its recorded access details/notice. My companion shows the seeded accepted pairing.
2. Preview a companion request and review it. It must show **Not sent**, with live submission disabled. No booking callable exists yet.
3. Choose **Open sample journey · signs out**, or Account → design preview. Open Activities → Morning tai chi → Request a companion → Review → Create sample request.
4. Switch the preview role to Coordinator → Requests → Choose companion → Assign sample companion.
5. Switch to Helper. Accept session → Start session → Finish session → Confirm my participation. The session must still await the elder.
6. Switch to Elder → My companion → Confirm my participation. The session shows **Confirmed by both**. Family has no participant-confirmation action.
7. Turn off sample family booking as Elder. Switch to Family: requests are hidden and creation is disabled. This does not change daily sharing. Reload to reset the sample journey.
8. Try BM, Preferences → Larger text/Gentler motion/Solid navigation, and phone/desktop widths.

## Verification on 21 October 2026

- `app/preview.ps1 -Mode check`: analyzer clean, **41 Flutter tests**, five browser-device bridge tests and two Firebase startup-order tests passed.
- `app/preview.ps1 -Mode build`: final release web build passed.
- `node app/tool/verify_community.mjs`: **33 real emulator read/permission checks** across all six demo accounts passed. This read-only check does not seed/reset domain data.
- Browser: live elder catalogue/access notice/pairing and unsent request review; explicit transition into samples; complete four-step journey with helper and elder confirmations; BM phone layout with larger text/reduced motion/solid navigation.
- Flutter tests cover consent withdrawal, stale-scope cleanup, expiry without navigation, invalid transitions, cancellation, duplicate intent, helper availability and BM/larger-text layouts at 320/390/768/1440 widths.
- Existing Stage 2 acceptance is recorded separately in [STAGE2_VERIFICATION.md](STAGE2_VERIFICATION.md); its mutating backend suite was not rerun/reset during this phase.

Screenshots: [activity catalogue](preview/phase2-activities.png), [completed sample session](preview/phase2-session-completed.png), [BM phone request form](preview/phase2-phone-bm.png).

## Needed from Developer B before real bookings

Provide the merged Stage 3 implementation, callable names, exact versioned input/response examples, stable errors and permitted read queries for availability changes, request creation, candidate/assignment reservation, acceptance, start/finish, cancellation and each participant's confirmation. Include consent revocation behavior, family-safe session visibility, conflict/retry handling and the authoritative completion state.

The form's duration/time choices and sample hours demonstrate the UI; they need alignment with B's validation and scheduling policy. Map UI values explicitly to the approved contract, retain one idempotency key per confirmed action across retries and let the server own actor authorization and recorded timestamps. Keep reward credits disabled until their own backend contract is available.

Backend Functions, rules, indexes, scripts and deployment configuration are unchanged. No cloud resources were provisioned.

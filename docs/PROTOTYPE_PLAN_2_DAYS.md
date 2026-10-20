# EmasCare: two-day prelim prototype and task split

**Current scope:** two developers, two days, one Flutter Web prototype with three role views. This replaces the three-day implementation plan for the prelim submission. The product plan remains the longer-term roadmap.

Assume eight working hours per person per day: 32 person-hours total. Plan 26 person-hours of work and reserve six for fixes. Person A should be the stronger Flutter/UI developer; Person B should be comfortable with Firebase and able to build a simple Flutter helper screen.

## What we are submitting

A working web app designed for phone screens, presented as an EmasCare module inside a mock Sime Darby Property app. On a laptop, show it in a phone-shaped frame; on a phone, open the same hosted link. Actual SDP integration is deferred.

There are three views inside the same app:

| View | Required functions |
| --- | --- |
| Elder | Daily Saya OK check-in, activity list, companion request, request status, family consent switches. |
| Family | Linked elder's permitted check-in/request updates; companion booking on the elder's behalf when enabled. |
| Helper | Availability toggle, own assigned requests, accept, complete. |

**Main demo:** elder checks in -> family sees the update -> elder or consented family requests a companion -> simple matching assigns a helper -> helper accepts and completes -> permitted views show completion.

Use three predefined demo accounts, a few seeded activities and approved helper profiles, and persisted check-ins/bookings. No coordinator account or dashboard is required.

## Recommended split: shared infrastructure plus feature ownership

A hybrid split gives A the elder/family experience and B the data layer/helper experience. A pure frontend/backend split puts all three views on A while B has a smaller backend after Cloud Functions are removed. Splitting every feature independently would make both developers duplicate Firebase and shared model work.

| Owner | Deliverable | Concrete tasks | Done when |
| --- | --- | --- | --- |
| A | App shell and presentation | Flutter scaffold, mock SDP home and EmasCare entry, phone layout, navigation, shared components, demo-account entry UI. | All three routes open and the layout works on phone and laptop. |
| A | Elder view | Saya OK, activity cards, companion form/status, separate daily-sharing and family-booking switches. | Check-in and request persist; consent changes are reflected in the UI. |
| A | Family view | Linked elder status, request history/status, reuse companion form for proxy booking. | Family can book with permission; disabled consent shows an appropriate state. |
| A | UI finish and release build | BM/EN copy for core actions, large targets, loading/error/pending states, Flutter analysis/build, screenshots and recording. | Core flow is readable and usable on the presentation device. |
| B | Firebase and shared data layer | Spark project configuration, email/password demo accounts, fixtures, Firestore rules, Dart models/repository, streams and mutations. | A can use one repository to read and write real demo data. |
| B | Matching and booking lifecycle | Simple candidate selection, duplicate-submit protection, helper reservation, accept/complete transitions. | One request gets one helper; repeated taps do not create duplicate bookings. |
| B | Helper view | Availability toggle, own queue, accept/complete buttons, server-stream updates. | Helper completes an assigned request and the other views update. |
| B | Hosting and handover | Hosting configuration/deployment, fixture reset, focused data/rules checks, short README/runbook. | Hosted link works and the demo can be reset and repeated. |
| Both | Integration and rehearsal | Agree shared methods first; integrate on Day 1; test separate accounts and rehearse on Day 2. | The complete journey runs twice from reset. |

## Keep the shared contract small

Agree these during the first hour; B owns the shared Dart models/repository and A consumes them. Use a compiling placeholder for B's helper screen until its UI is ready.

- Models: session/profile, consent settings, daily check-in, activity, helper, companion request.
- Reads: current session, activities, current elder's check-in/settings, permitted requests, own helper availability/queue.
- Actions: login/logout, submit check-in, save consent, create request, retry matching, set availability, accept request, complete request.
- Request states: `pending -> assigned -> accepted -> completed`. No match leaves the request `pending`; show a retry action rather than claiming assignment succeeded.
- Both elder and linked family use the same booking form/repository method. Family booking requires current booking consent; check-in visibility uses separate sharing consent. Family cannot edit either switch.
- Use one client-generated request ID per confirmed submission and retain it across retries. Read-only status refreshes must never create another request.

No TypeScript Functions project or versioned wire-schema framework is needed for this prototype.

## Simple matching and free-tier boundaries

Use Flutter Web, Firebase Authentication email/password accounts, Firestore, and static Firebase Hosting on Spark. Use the supplied hosting address and bundled images. Remain within the published free quotas; do not enable billing-dependent services. See [Firebase pricing](https://firebase.google.com/pricing).

Matching runs in the prototype's Dart repository when a request is confirmed or explicitly retried. Choose the first approved, available helper who supports the task. A helper has at most one active booking in this demo; a Firestore transaction checks and sets that helper's reservation together with the assigned request. If the helper is already reserved, try another candidate or leave the request pending. Accept/complete validate the current request state and assigned helper; completion releases the reservation.

Keep basic Firestore access rules: users cannot edit their role or approval, family access follows the seeded relationship and elder consent, and helpers read/act only on their own assignments. Client matching is demo behavior; it is not a trusted server matching service.

Defer coordinator UI, Cloud Functions, scheduled missed-check-in alerts, advanced time-slot matching, recurring pairings, two-sided completion, support/report workflows, coins/vouchers, uploads, and native app builds. Voice AI is outside the core two-day scope. Add a small AI draft only after the main flow passes and if the submission requires it; never expose an AI service key in the app.

## Two-day schedule

Hours are working hours within each day. Shared blocks count against both developers' time.

| Day / hours | Person A | Person B | Checkpoint |
| --- | --- | --- | --- |
| Day 1, 0-1 | Create shell and role routes; agree repository calls with B. | Agree models/states; create repository interface and helper placeholder; check Firebase access. | Integrated scaffold builds; both branch from it. |
| Day 1, 1-3 | Elder home, check-in, activities; use agreed fixture shapes while B connects Firebase. | Firebase configuration, demo accounts/data, basic rules, login/read/check-in repository methods. | Auth and persisted check-in work. |
| Day 1, 3-5 | Shared booking form, elder request status, family view and consent UI. | Request creation/matching, reservation and request streams; accept/complete methods. | Request can be persisted and assigned. |
| Day 1, 5-6 | Connect elder/family screens to the real repository; fix integration mismatches. | Build helper screen using the same repository. | All three views use real demo data. |
| Day 1, 6-7 | Integrate and run the complete journey with B. | Integrate, deploy first working version, run the journey with A. | First hosted end-to-end flow; freeze feature scope. |
| Day 1, 7-8 | Fix blockers. | Fix blockers. | One reserve hour each. |
| Day 2, 0-2 | BM/EN core copy, large text/targets, loading/error/no-helper/consent states. | Check permissions, retries, reservations, availability and state transitions; fix failures. | Core flow and failure states work. |
| Day 2, 2-3 | Analyze/build release; check presentation-device layout. | Deploy the integrated release and verify persisted data. | Submission candidate is hosted. |
| Day 2, 3-4 | Test elder/family flows across separate accounts with B. | Test helper flow, consent withdrawal and duplicate requests with A. | Submission checks pass. |
| Day 2, 4-6 | Rehearse twice; capture screenshots and backup recording. | Verify reset; finish runbook, URL and account handover. | Submission package ready. |
| Day 2, 6-8 | Fix release blockers only. | Fix release blockers only. | Two reserve hours each. |

If the Day 1 journey fails, use the reserve to finish it. Do not start AI or add extra features. Once Day 2 begins, prioritize fixes and presentation of the agreed core.

## Files and merge rules

| Owner | Paths |
| --- | --- |
| A | `app/lib/main.dart`, `app/lib/app/**`, `app/lib/shared/**`, `app/lib/features/elder/**`, `app/lib/features/family/**`, localization/assets, `app/pubspec.*`, app platform/scaffold files. |
| B | `app/lib/data/**`, `app/lib/firebase_options.dart`, `app/lib/features/helper/**`, Firebase root configuration/rules/indexes, seed/reset scripts, data/rules checks, root README/docs. |

- A owns dependencies and navigation; B supplies the helper screen without editing the router. B owns Firebase setup; review generated changes to A's files together.
- Use separate clones/worktrees. After the shared scaffold lands, use short A/B branches and integrate before the Day 1 checkpoint.
- Merge B's repository changes before UI consumers. Keep shared method changes additive and tell the other developer immediately.
- B deploys the integrated commit. Do not reset demo data during another person's test run.

## Submission checks

- [ ] Mock SDP home opens EmasCare; all three role views work.
- [ ] Check-in persists after refresh and appears for the linked, consented family.
- [ ] Elder and permitted family can each create a companion request.
- [ ] Matching assigns an eligible available helper; no eligible helper produces an honest pending state.
- [ ] Duplicate submission/retry produces one request; competing assignments cannot reserve the same helper twice.
- [ ] Assigned helper accepts/completes; permitted elder/family views update; reservation is released.
- [ ] Unrelated accounts cannot read another elder's records; family cannot change consent or book after it is withdrawn; helper cannot act on another helper's request.
- [ ] `flutter analyze` and `flutter build web --release` pass; focused data/rules checks pass.
- [ ] Hosted URL, secure demo-account handover, reset instructions, limitations, screenshots and backup recording are ready.
- [ ] Two rehearsals complete from reset using separate authenticated accounts.

This is a task allocation and implementation plan. The repository still needs the app, Firebase setup, checks, and deployment described above.

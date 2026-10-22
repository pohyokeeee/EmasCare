# Phase 4: saved activity attendance

The owner reviewed the five-step attendance proposal and authorized building it with apple-design on `ui-phase-4`. Base: merged main `d3bd841`. Developer A owns Flutter; B's Stage 4 backend, rules, indexes and scripts remain unchanged. Leave changes uncommitted until requested.

## Reviewed design and implementation tasks

Use the existing Activities destination rather than adding another phone navigation item: Upcoming, Past activities and Attendance history for elder/family, with helper browsing read-only. A separate history destination would crowd the phone bar; a single mixed feed would obscure pending attendance. Coordinator Requests gains Companion requests / Attendance review tabs. Keep the forest green/warm white Manrope design, restrained surfaces, instant interruptible press feedback, reduced motion, solid navigation and BM/EN.

1. Add exact typed attendance records and a separate AttendanceRepository. Connect `submitActivityAttendance` and `reviewActivityAttendance` with version 1 envelopes, immutable per-action retry keys, and documented scoped streams. Never compute backend IDs or write Firestore directly.
2. Add a controller bound to server role/township/household and the selected family elder's **sharing** consent. Helpers never subscribe. Clear records, pending commands and open private details on scope loss or permission failure; streams remain authoritative over old callable receipts.
3. Add ended in-person activity submission, submitted/verified/rejected feedback and readable history with review notes. Existing companion-managed attendance stays in its own confirmation flow and cannot be submitted twice. Activity boundary timers update eligibility while a sheet stays open.
4. Add coordinator's submitted review queue and a deliberate review sheet: activity, elder reference, trusted evidence method and factual note for verification; reason and null method for rejection. Both outcomes are terminal. A disappearing queue row must not strand a successful sheet or cause a dismissed sheet to navigate later.
5. Fix the local emulator warning's obstruction of narrow navigation while retaining clear in-app local-demo labels. Run fixture/controller/widget, existing Flutter/JS, release build, backend regressions and real multi-account browser checks. Check BM/larger text at 320/390/768/1440 widths, retries, sharing withdrawal/restoration, refresh, verification/rejection, timing and session deduplication. Record files/results/startup and screenshots in the handover.

## Boundaries and acceptance

No family/helper proxy submission, QR/upload flow, reward credits/redemption, voice AI, deployment or reporting aggregates. The backend creates pending-policy claims after verification and owns completion timestamps/identities; the UI shows attendance facts without fabricated coins or totals. Use the seeded past activity for immediate verification and the existing ready phone session for Stage 3 regression. Use only synthetic evidence when reviewing emulator fixtures.

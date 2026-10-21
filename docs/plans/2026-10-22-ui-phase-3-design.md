# Phase 3: live companion sessions

The owner reviewed the five-step Phase 3 proposal (real requests, coordinator assignment, helper availability/lifecycle, separate confirmations, complete testing), then approved implementation using apple-design on the exact branch `ui-phase-3`. Base: merged main `adb1b63`, including B's Stage 3 and subsequent Stage 4 backend. Stage 4 attendance UI and reward/voice features remain outside this change.

## Design and implementation

Keep the existing warm white/forest green Manrope interface, instant spring press feedback, familiar bottom sheets, generous hierarchy, reduced motion, solid navigation and BM/EN. Use real status cards with date, place, companion and an explicit next action. Present separate confirmations in place; show timing explanations when a scheduled action is unavailable.

Add a separate typed session repository and controller beside the Stage 2 session/auth controller. This avoids mixing preview actions with saved mutations. Scope request subscriptions by authenticated profile and selected family elder/current booking consent; coordinator queues use one selected state. Cancel and clear records, pending actions and affected sheets on scope loss. Every confirmed mutation has one frozen payload and idempotency key retained for retries. Stream state remains authoritative over replayed callable results.

Live booking uses server catalogue IDs, explicit null IDs for phone help, exact activity intervals, supported language/gender preferences and minute-aligned future times for standalone help. Unsupported free-text notes stay in preview only. Helper availability supports multiple weekly intervals, including full-day end 24:00. Coordinator candidates come from accepted same-township pairings; the backend validates approval, task, availability, preferences and reservations.

Keep the existing labelled in-memory preview available. Live success requires real callable completion; no sample fallback or invented coins. No backend Functions, rules, indexes or scripts are edited. Leave implementation uncommitted until requested.

## Verification gates

Parse Stage 3 fixtures and timestamps; exercise exact request payloads, scoped subscriptions, frozen retry identity, duplicate taps, stale results, consent withdrawal and separate confirmation roles. Test live widgets and all four roles at 320/390/768/1440 widths with BM/larger text. Run Flutter analysis/tests, browser bridge checks and release build. Run backend regression checks on local emulators and the real browser flows: request/assignment, scheduled-action boundaries, ready phone session through both confirmations, availability, cancellation, consent withdrawal/restoration and refresh persistence. Record source files, results, screenshots and exact local startup steps.

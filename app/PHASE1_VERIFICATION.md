# Phase 1 verification — 21 October 2026

Scope: Developer A's local Flutter Web foundation and four-role interface preview. This is separate from completion of the full connected MVP.

| Requirement | Evidence / result |
| --- | --- |
| Initial delivery on a new branch | Built and verified on `codex/phase-1-ui`, with `main` unchanged. Publishing the branch and opening a pull request were authorized separately after local review. |
| Runnable Flutter Web app | Release build succeeded through `preview.ps1 -Mode build`; final build loaded at `http://127.0.0.1:8080`. |
| Shared components and Apple design principles | Shared theme, cards, badges, sheets, Manrope weights, immediate press feedback with interruptible critically damped springs, translucent navigation over scrolling content. |
| Accessibility preferences | Larger text, reduced motion and solid navigation verified in browser; semantic switch labels verified in the final build. System motion/transparency/contrast preferences are read at startup. |
| Four distinct role previews | Elder, Family, Helper and Coordinator navigated in the browser. Coordinator is read-only. |
| Responsive phone/tablet/desktop | Every role/section tested at 320, 390, 768 and 1440 px with BM and larger text. Browser screenshots reviewed at 390 and 1440 px, plus 320 px with larger BM text. |
| BM/EN core text | Browser language switch and Malay larger-text layout verified. Some synthetic coordinator descriptions remain English, as documented. |
| Shared models/repository seam | UI view models plus injected `EmasRepository` / `MockEmasRepository`; no unapproved wire JSON or Firebase credentials. |
| Local check-in / family visibility | Pressing Saya OK updates the Elder state and the sample Family status. Reload resets it. No check-in is sent. |
| Local helper availability | Switch toggled in browser and test; no availability mutation reaches a coordinator/backend. |
| Catalog navigation | Community filter, activity access sheet and companion navigation verified in browser and tests. |
| Routes/history | Family hash deep link loaded the right role; browser Back restored Today; reload retained the role/route while resetting local state. |
| Reward boundaries | Wallet has no invented balance/rates; 100-coin voucher is illustrative and redemption is disabled. Per-completion elder/helper reward wording replaces the old monthly award. |
| Browser voice feasibility | Localhost secure context and recording/speech APIs available; microphone permission remains `prompt`. Recording/playback logic, denied permission and track cleanup pass fixture tests. Actual microphone capture was not performed. |
| Spoken-read-back gap | This in-app browser has no installed speech voices; a clear fallback message displayed. Audible BM/EN read-back and recording still need testing on the presentation device. |
| Backend boundary | No authentication, persisted consent/check-ins, booking, session lifecycle, coin award, redemption or AI parsing is connected in Phase 1. Tanya Dulu remains excluded. |
| Runtime errors | No console warnings/errors observed during the final browser check. |

Final commands:

- `preview.ps1 -Mode check`: analyzer clean, **8 Flutter tests + 5 browser-bridge tests passed**.
- `preview.ps1 -Mode build`: release build succeeded with local rendering assets and no generated service-worker cache.
- `preview.ps1 -Mode serve -Port 8080`: local server used for the browser walkthrough.

Saved screenshots:

- [Elder desktop](preview/elder-desktop.jpg)
- [Elder phone](preview/elder-phone.jpg)
- [Larger Malay text on a 320 px phone](preview/elder-phone-bm-large.jpg)
- [Family after local sample check-in](preview/family-desktop.jpg)
- [Coordinator sample overview](preview/coordinator-desktop.jpg)

These results establish the Phase 1 preview boundaries above. They do not establish live backend permissions, real resident attendance, reward correctness, accessibility certification, or presentation-device audio acceptance.

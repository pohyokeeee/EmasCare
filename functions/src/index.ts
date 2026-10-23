import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {setGlobalOptions} from "firebase-functions/v2";
import {onCall} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {authenticatedUid, authorizeElder, loadActor, requireRole, requireTownship} from "./auth";
import {runCommand} from "./commands";
import {fail} from "./errors";
import {documentId, envelope, inputObject, stringField} from "./validation";
import {createCheckInService} from "./checkins";
import {createSessionService} from "./sessions";
import {createAttendanceService} from "./attendance";
import {createWalletService} from "./wallet";
import {createOperationsService} from "./operations";
import {createNotificationService} from "./notifications";
import {createSummaryService} from "./summaries";
import {createVoiceService} from "./voice";
import {createChatService} from "./chat";
import {createMonthlyRewardService} from "./monthly_rewards";

initializeApp();
setGlobalOptions({region: "asia-southeast1", maxInstances: 3});
const db = getFirestore();
const checkins = createCheckInService(db);
const sessions = createSessionService(db);
const attendance = createAttendanceService(db);
const wallet = createWalletService(db);
const operations = createOperationsService(db);
const notifications = createNotificationService(db);
const summaries = createSummaryService(db);
const voice = createVoiceService(db);
const chat = createChatService(db);
const monthlyRewards = createMonthlyRewardService(db);

export const saveElderSettings = onCall((request) => checkins.saveElderSettings(authenticatedUid(request.auth), request.data));
export const submitCheckIn = onCall((request) => checkins.submitCheckIn(authenticatedUid(request.auth), request.data));
export const recordPhoneResponse = onCall((request) => checkins.recordPhoneResponse(authenticatedUid(request.auth), request.data));
export const setHelperAvailability = onCall((request) => sessions.setHelperAvailability(authenticatedUid(request.auth), request.data));
export const setCompanionAvailability = onCall((request) => sessions.setCompanionAvailability(authenticatedUid(request.auth), request.data));
export const createRequest = onCall((request) => sessions.createRequest(authenticatedUid(request.auth), request.data));
export const assignRequest = onCall((request) => sessions.assignRequest(authenticatedUid(request.auth), request.data));
export const transitionRequest = onCall((request) => sessions.transitionRequest(authenticatedUid(request.auth), request.data));
export const submitActivityAttendance = onCall((request) => attendance.submitActivityAttendance(authenticatedUid(request.auth), request.data));
export const reviewActivityAttendance = onCall((request) => attendance.reviewActivityAttendance(authenticatedUid(request.auth), request.data));
export const redeemDemoVoucher = onCall((request) => wallet.redeemDemoVoucher(authenticatedUid(request.auth), request.data));
export const setPlaceWarning = onCall((r) => operations.setPlaceWarning(authenticatedUid(r.auth), r.data));
export const submitReport = onCall((r) => operations.submitReport(authenticatedUid(r.auth), r.data));
export const reviewReport = onCall((r) => operations.reviewReport(authenticatedUid(r.auth), r.data));
export const blockHelper = onCall((r) => operations.blockHelper(authenticatedUid(r.auth), r.data));
export const sendFamilyCheer = onCall((r) => operations.sendFamilyCheer(authenticatedUid(r.auth), r.data));
export const markNotificationRead = onCall((r) => notifications.markNotificationRead(authenticatedUid(r.auth), r.data));
export const processDemoDueItems = onCall((r) => checkins.processDemoDueItems(authenticatedUid(r.auth), r.data));
export const getProgress = onCall((r) => summaries.getProgress(authenticatedUid(r.auth), r.data));
export const getAvailabilitySummary = onCall((r) => summaries.getAvailabilitySummary(authenticatedUid(r.auth), r.data));
export const getCoordinatorSummary = onCall((r) => summaries.getCoordinatorSummary(authenticatedUid(r.auth), r.data));
export const parseVoiceBooking = onCall({timeoutSeconds: 40, memory: "256MiB"}, (r) => voice.parseVoiceBooking(authenticatedUid(r.auth), r.data));
export const listSessionMessages = onCall((r) => chat.listSessionMessages(authenticatedUid(r.auth), r.data));
export const sendSessionMessage = onCall((r) => chat.sendSessionMessage(authenticatedUid(r.auth), r.data));
export const settleDueMonthlyRewards = onCall((r) => monthlyRewards.settleDueMonthlyRewards(authenticatedUid(r.auth), r.data));
export const settleDueMonthlyRewardsScheduled = onSchedule({
  schedule: "0 0 1 * *",
  timeZone: "Asia/Kuala_Lumpur",
  timeoutSeconds: 540,
}, async () => {
  const result = await monthlyRewards.settleDueMonthlyRewardsScheduled();
  console.log("Monthly reward settlement completed", result);
});

// Foundation diagnostics only; not replacements for agreed domain callables.
export const getBackendContext = onCall(async (request) => {
  const uid = authenticatedUid(request.auth);
  inputObject(request.data, []);
  const actor = await loadActor(db, uid);
  return envelope({profile: actor});
});

// This write probe is registered ONLY by the local Functions emulator. It cannot
// be deployed and never touches domain records, wallets or reward policies.
if (process.env.FUNCTIONS_EMULATOR === "true") {
  exports.foundationProbe = onCall(async (request) => {
    const uid = authenticatedUid(request.auth);
    const input = inputObject(request.data, ["townshipId", "note", "elderId", "consentScope"], true);
    const townshipId = documentId(input.townshipId);
    const note = stringField(input.note, "INVALID_NOTE", 200);
    const elderId = input.elderId === undefined ? null : documentId(input.elderId);
    const consentScope = input.consentScope;
    if (elderId && consentScope !== "daily_sharing" && consentScope !== "family_booking") {
      fail("invalid-argument", "INVALID_CONSENT_SCOPE");
    }
    if (!elderId && consentScope !== undefined) fail("invalid-argument", "INVALID_CONSENT_SCOPE");
    return runCommand({db, uid, name: "foundationProbe", key: input.idempotencyKey as string,
      payload: {townshipId, note, elderId, consentScope: consentScope ?? null},
      authorize: async (tx, actor) => {
        requireTownship(actor, townshipId);
        if (elderId) await authorizeElder(db, tx, actor, elderId, consentScope as "daily_sharing" | "family_booking");
        else requireRole(actor, ["coordinator"]);
      },
      execute: async (tx, actor) => {
        const ref = db.doc(`foundationProbes/${actor.uid}`);
        const before = await tx.get(ref);
        const count = (before.data()?.count ?? 0) + 1;
        const recordedAt = Timestamp.now();
        tx.set(ref, {actorUid: actor.uid, count, note, updatedAt: recordedAt});
        return envelope({probe: {count, note, recordedAt: recordedAt.toDate().toISOString()}});
      },
    });
  });
}

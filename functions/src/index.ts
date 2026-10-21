import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {setGlobalOptions} from "firebase-functions/v2";
import {onCall} from "firebase-functions/v2/https";
import {authenticatedUid, authorizeElder, loadActor, requireRole, requireTownship} from "./auth";
import {runCommand} from "./commands";
import {fail} from "./errors";
import {documentId, envelope, inputObject, stringField} from "./validation";
import {createCheckInService} from "./checkins";

initializeApp();
setGlobalOptions({region: "asia-southeast1", maxInstances: 3});
const db = getFirestore();
const checkins = createCheckInService(db);

export const saveElderSettings = onCall((request) => checkins.saveElderSettings(authenticatedUid(request.auth), request.data));
export const submitCheckIn = onCall((request) => checkins.submitCheckIn(authenticatedUid(request.auth), request.data));
export const recordPhoneResponse = onCall((request) => checkins.recordPhoneResponse(authenticatedUid(request.auth), request.data));

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

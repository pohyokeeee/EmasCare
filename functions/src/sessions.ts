import {DocumentData, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {Actor, authorizeElder, loadActor, requireRole, requireTownship} from "./auth";
import {runCommand, tupleId} from "./commands";
import {fail} from "./errors";
import {documentId, envelope, inputObject} from "./validation";
import {covers, daySegments, isoTime, slotsInput, taskTiers, Task, wireRecord} from "./scheduling";
import {activityLockId, attendanceId, completeSession} from "./completions";

export function reservationId(helperId: string, localDate: string): string { return tupleId("helper-date", helperId, localDate); }
export function helperBlockId(elderId: string, helperId: string): string { return tupleId("helper-block", elderId, helperId); }

async function elderHousehold(db: Firestore, tx: Transaction, elder: Actor) {
  if (!elder.householdId) fail("failed-precondition", "ELDER_HOUSEHOLD_REQUIRED");
  const household = (await tx.get(db.doc(`households/${elder.householdId}`))).data();
  if (!household || household.townshipId !== elder.townshipId || !household.elderIds?.includes(elder.uid) ||
      !household.memberUids?.includes(elder.uid)) fail("permission-denied", "UNRELATED_HOUSEHOLD");
}

async function requestAccess(db: Firestore, tx: Transaction, actor: Actor, id: string) {
  const snap = await tx.get(db.doc(`requests/${id}`));
  if (!snap.exists) fail("not-found", "REQUEST_NOT_FOUND");
  const request = snap.data()!;
  requireTownship(actor, request.townshipId);
  if (actor.role === "coordinator") return request;
  if (actor.role === "helper") {
    if (request.helperId !== actor.uid) fail("permission-denied", "NOT_ASSIGNED_HELPER");
  } else {
    await authorizeElder(db, tx, actor, request.elderId, "family_booking");
    const elder = await loadActor(db, request.elderId, tx);
    await elderHousehold(db, tx, elder);
    if (elder.householdId !== request.householdId) fail("permission-denied", "UNRELATED_HOUSEHOLD");
  }
  return request;
}

async function reservations(db: Firestore, tx: Transaction, request: DocumentData, helperId: string) {
  const refs = daySegments(request.startsAt, request.endsAt).map(({localDate}) => db.doc(`helperReservations/${reservationId(helperId, localDate)}`));
  const snapshots = await tx.getAll(...refs);
  return snapshots.map((snap, index) => ({ref: refs[index]!, data: snap.data(), localDate: daySegments(request.startsAt, request.endsAt)[index]!.localDate}));
}

function release(tx: Transaction, rows: Awaited<ReturnType<typeof reservations>>, id: string, now: Timestamp) {
  for (const row of rows) if (row.data) tx.update(row.ref, {slots: row.data.slots.filter((slot: DocumentData) => slot.requestId !== id), updatedAt: now});
}

async function helperSafety(db: Firestore, tx: Transaction, request: DocumentData, helperId: string) {
  const profile = (await tx.get(db.doc(`helperProfiles/${helperId}`))).data();
  const block = await tx.get(db.doc(`helperBlocks/${helperBlockId(request.elderId, helperId)}`));
  if (block.exists) fail("failed-precondition", "HELPER_BLOCKED");
  if (!profile?.approved) fail("failed-precondition", "PAIRING_NOT_ELIGIBLE");
  return profile;
}

export function createSessionService(db: Firestore, clock: () => Timestamp = Timestamp.now) {
  async function setHelperAvailability(uid: string, value: unknown) {
    const input = inputObject(value, ["available", "slots"], true);
    if (typeof input.available !== "boolean") fail("invalid-argument", "INVALID_AVAILABILITY");
    const slots = slotsInput(input.slots);
    return runCommand({db, uid, name: "setHelperAvailability", key: input.idempotencyKey as string,
      payload: {available: input.available, slots}, authorize: async (tx, actor) => {
        requireRole(actor, ["helper"]);
        const profile = (await tx.get(db.doc(`helperProfiles/${actor.uid}`))).data();
        if (!profile) fail("failed-precondition", "HELPER_PROFILE_REQUIRED");
        return profile;
      }, execute: async (tx, actor, profile) => {
        const next = {...profile, available: input.available, availabilitySlots: slots, updatedAt: clock()};
        tx.set(db.doc(`helperProfiles/${actor.uid}`), next);
        return envelope({helperProfile: wireRecord(actor.uid, next)});
      }});
  }

  async function createRequest(uid: string, value: unknown) {
    const input = inputObject(value, ["elderId", "activityId", "placeId", "startsAt", "endsAt", "taskType", "preferredLanguage", "preferredHelperGender"], true);
    const elderId = documentId(input.elderId);
    const activityId = input.activityId === null ? null : documentId(input.activityId);
    const placeId = input.placeId === null ? null : documentId(input.placeId);
    const start = isoTime(input.startsAt), end = isoTime(input.endsAt);
    if (end.toMillis() <= start.toMillis() || end.toMillis() - start.toMillis() > 86400000) fail("invalid-argument", "INVALID_TIME_RANGE");
    if (typeof input.taskType !== "string" || !Object.hasOwn(taskTiers, input.taskType)) fail("invalid-argument", "INVALID_TASK");
    if (!["bm", "en"].includes(input.preferredLanguage as string) || !["any", "female", "male"].includes(input.preferredHelperGender as string)) {
      fail("invalid-argument", "INVALID_PREFERENCES");
    }
    if ((input.taskType === "phone_help" && (activityId || placeId)) || (input.taskType !== "phone_help" && !placeId)) {
      fail("invalid-argument", "INVALID_PLACE");
    }
    const payload = {elderId, activityId, placeId, startsAt: start.toDate().toISOString(), endsAt: end.toDate().toISOString(),
      taskType: input.taskType, preferredLanguage: input.preferredLanguage, preferredHelperGender: input.preferredHelperGender};
    const id = tupleId("request", uid, input.idempotencyKey as string);
    return runCommand({db, uid, name: "createRequest", key: input.idempotencyKey as string, payload,
      authorize: async (tx, actor) => {
        requireRole(actor, ["elder", "family"]);
        await authorizeElder(db, tx, actor, elderId, "family_booking");
        const elder = await loadActor(db, elderId, tx);
        await elderHousehold(db, tx, elder);
        return elder;
      }, execute: async (tx, actor, elder) => {
        const now = clock();
        if (start.toMillis() <= now.toMillis()) fail("invalid-argument", "INVALID_TIME_RANGE");
        if (placeId) {
          const place = (await tx.get(db.doc(`places/${placeId}`))).data();
          if (!place) fail("not-found", "PLACE_NOT_FOUND");
          requireTownship(actor, place.townshipId);
        }
        if (activityId) {
          const activity = (await tx.get(db.doc(`activities/${activityId}`))).data();
          if (!activity) fail("not-found", "ACTIVITY_NOT_FOUND");
          requireTownship(actor, activity.townshipId);
          if (activity.participationMode !== "in_person" || activity.placeId !== placeId ||
              activity.startsAt.toMillis() !== start.toMillis() || activity.endsAt.toMillis() !== end.toMillis()) {
            fail("invalid-argument", "ACTIVITY_SCHEDULE_MISMATCH");
          }
          const lock = (await tx.get(db.doc(`activityElderLocks/${activityLockId(activityId, elderId)}`))).data();
          const attendance = (await tx.get(db.doc(`activityAttendances/${attendanceId(activityId, elderId)}`))).data();
          if (lock?.state === "completed" || attendance?.status === "verified") fail("failed-precondition", "ACTIVITY_ALREADY_COMPLETED");
          if (lock?.requestId) fail("failed-precondition", "ACTIVITY_REQUEST_EXISTS");
        }
        const request = {...payload, startsAt: start, endsAt: end, townshipId: actor.townshipId, householdId: elder.householdId,
          createdBy: actor.uid, state: "requested", pairingId: null, helperId: null, elderDisplayName: elder.displayName,
          helperDisplay: null, assignedAt: null, acceptedAt: null, startedAt: null, finishedAt: null,
          elderConfirmation: null, helperConfirmation: null, completedAt: null, cancelledAt: null,
          completionEventId: null, participationIds: {elder: null, helper: null}, createdAt: now, updatedAt: now};
        if (activityId) tx.set(db.doc(`activityElderLocks/${activityLockId(activityId, elderId)}`),
          {activityId, elderId, townshipId: actor.townshipId, requestId: id, state: "active", updatedAt: now});
        tx.create(db.doc(`requests/${id}`), request);
        return envelope({request: wireRecord(id, request)});
      }});
  }

  async function assignRequest(uid: string, value: unknown) {
    const input = inputObject(value, ["requestId", "pairingId"], true);
    const id = documentId(input.requestId), pairingId = documentId(input.pairingId);
    return runCommand({db, uid, name: "assignRequest", key: input.idempotencyKey as string, payload: {requestId: id, pairingId},
      authorize: async (tx, actor) => { requireRole(actor, ["coordinator"]); return requestAccess(db, tx, actor, id); },
      execute: async (tx, actor, request) => {
        const now = clock();
        if (request.state !== "requested") fail("failed-precondition", "INVALID_TRANSITION");
        if (request.startsAt.toMillis() <= now.toMillis()) fail("failed-precondition", "SESSION_ALREADY_DUE");
        const pair = (await tx.get(db.doc(`pairings/${pairingId}`))).data();
        if (!pair || pair.townshipId !== actor.townshipId || pair.elderId !== request.elderId || !pair.active ||
            !pair.elderAccepted || !pair.helperAccepted || !pair.allowedTasks?.includes(request.taskType) ||
            typeof pair.trialStartsOn !== "string" || typeof pair.trialEndsOn !== "string" ||
            !/^\d{4}-\d\d-\d\d$/.test(pair.trialStartsOn) || !/^\d{4}-\d\d-\d\d$/.test(pair.trialEndsOn)) {
          fail("failed-precondition", "PAIRING_NOT_ELIGIBLE");
        }
        const helper = await loadActor(db, pair.helperId, tx);
        if (helper.role !== "helper" || helper.uid === request.elderId) fail("failed-precondition", "PAIRING_NOT_ELIGIBLE");
        requireTownship(actor, helper.townshipId);
        const profile = await helperSafety(db, tx, request, helper.uid);
        const tier = {T1: 1, T2: 2, T3: 3}[profile.tier as "T1" | "T2" | "T3"] ?? 0;
        const days = daySegments(request.startsAt, request.endsAt);
        if (tier < taskTiers[request.taskType as Task] || !profile.allowedTasks?.includes(request.taskType) ||
            !profile.languages?.includes(request.preferredLanguage) ||
            (request.preferredHelperGender !== "any" && profile.gender !== request.preferredHelperGender) ||
            days.some((day) => day.localDate < pair.trialStartsOn || day.localDate > pair.trialEndsOn) ||
            !covers(pair.cadence ?? [], request.startsAt, request.endsAt)) fail("failed-precondition", "PAIRING_NOT_ELIGIBLE");
        if (!profile.available || !covers(profile.availabilitySlots ?? [], request.startsAt, request.endsAt)) fail("failed-precondition", "HELPER_UNAVAILABLE");
        const rows = await reservations(db, tx, request, helper.uid);
        for (const row of rows) if ((row.data?.slots ?? []).some((slot: DocumentData) =>
          slot.requestId !== id && slot.startsAt.toMillis() < request.endsAt.toMillis() && slot.endsAt.toMillis() > request.startsAt.toMillis())) {
          fail("failed-precondition", "HELPER_UNAVAILABLE");
        }
        const next = {...request, state: "assigned", pairingId, helperId: helper.uid,
          helperDisplay: {displayName: helper.displayName, tier: profile.tier}, assignedAt: now, updatedAt: now};
        for (const row of rows) tx.set(row.ref, {helperId: helper.uid, townshipId: actor.townshipId, localDate: row.localDate,
          slots: [...(row.data?.slots ?? []), {requestId: id, startsAt: request.startsAt, endsAt: request.endsAt}], updatedAt: now});
        tx.set(db.doc(`requests/${id}`), next);
        return envelope({request: wireRecord(id, next)});
      }});
  }

  async function transitionRequest(uid: string, value: unknown) {
    const input = inputObject(value, ["requestId", "action"], true);
    const id = documentId(input.requestId), action = input.action as string;
    if (!["accept", "start", "finish", "confirm", "cancel"].includes(action)) fail("invalid-argument", "INVALID_ACTION");
    return runCommand({db, uid, name: "transitionRequest", key: input.idempotencyKey as string, payload: {requestId: id, action},
      authorize: async (tx, actor) => {
        const request = await requestAccess(db, tx, actor, id);
        if (["accept", "start", "finish"].includes(action) && (actor.role !== "helper" || request.helperId !== actor.uid)) {
          fail("permission-denied", "NOT_ASSIGNED_HELPER");
        }
        if (action === "confirm" && !(actor.role === "elder" && actor.uid === request.elderId) &&
            !(actor.role === "helper" && actor.uid === request.helperId)) fail("permission-denied", "ROLE_NOT_ALLOWED");
        if (action === "cancel") requireRole(actor, ["elder", "family", "coordinator"]);
        return request;
      }, execute: async (tx, actor, request) => {
        const now = clock();
        const next = {...request};
        if ((action === "confirm" && request.state === "completed") || (action === "cancel" && request.state === "cancelled")) {
          return envelope({request: wireRecord(id, request)});
        }
        const required = {accept: "assigned", start: "accepted", finish: "in_progress", confirm: "awaiting_confirmation"};
        if (action === "cancel" ? !["requested", "assigned", "accepted"].includes(request.state) : request.state !== required[action as keyof typeof required]) {
          fail("failed-precondition", "INVALID_TRANSITION");
        }
        if (action === "start" || action === "accept") await helperSafety(db, tx, request, actor.uid);
        if (action === "start" && now.toMillis() < request.startsAt.toMillis()) fail("failed-precondition", "SESSION_NOT_STARTED");
        if (action === "start" && request.activityId && now.toMillis() >= request.endsAt.toMillis()) fail("failed-precondition", "ACTIVITY_ALREADY_FINISHED");
        if (action === "finish" && request.activityId && now.toMillis() < request.endsAt.toMillis()) fail("failed-precondition", "ACTIVITY_NOT_FINISHED");
        const rows = request.helperId ? await reservations(db, tx, request, request.helperId) : [];
        const sessionRef = request.helperId ? db.doc(`helperSessions/${request.helperId}`) : null;
        const active = sessionRef && ["start", "finish"].includes(action) ? (await tx.get(sessionRef)).data() : null;
        if (action === "start" && active?.requestId && active.requestId !== id) fail("failed-precondition", "HELPER_BUSY");
        let lock: DocumentData | undefined;
        const lockRef = request.activityId ? db.doc(`activityElderLocks/${activityLockId(request.activityId, request.elderId)}`) : null;
        if (lockRef && ["cancel", "confirm"].includes(action)) lock = (await tx.get(lockRef)).data();
        if (action === "confirm" && lock?.requestId && lock.requestId !== id) fail("failed-precondition", "ACTIVITY_REQUEST_EXISTS");
        if (action === "confirm") {
          const field = actor.role === "elder" ? "elderConfirmation" : "helperConfirmation";
          if (request[field]) return envelope({request: wireRecord(id, request)});
          next[field] = {uid: actor.uid, at: now};
          if (next.elderConfirmation && next.helperConfirmation) {
            if (request.activityId && now.toMillis() < request.endsAt.toMillis()) fail("failed-precondition", "ACTIVITY_NOT_FINISHED");
            Object.assign(next, await completeSession(db, tx, id, request, now), {state: "completed", completedAt: now});
            release(tx, rows, id, now);
            if (lockRef) tx.set(lockRef, {...lock, activityId: request.activityId, elderId: request.elderId,
              townshipId: request.townshipId, requestId: id, state: "completed", updatedAt: now});
          }
        } else if (action === "cancel") {
          Object.assign(next, {state: "cancelled", cancelledAt: now});
          release(tx, rows, id, now);
          if (lockRef && lock?.requestId === id) tx.delete(lockRef);
        } else {
          const state = {accept: "accepted", start: "in_progress", finish: "awaiting_confirmation"}[action as "accept" | "start" | "finish"];
          const field = {accept: "acceptedAt", start: "startedAt", finish: "finishedAt"}[action as "accept" | "start" | "finish"];
          Object.assign(next, {state, [field]: now});
          if (action === "start") tx.set(sessionRef!, {helperId: actor.uid, townshipId: actor.townshipId, requestId: id, updatedAt: now});
          if (action === "finish" && active?.requestId === id) tx.set(sessionRef!, {helperId: actor.uid, townshipId: actor.townshipId, requestId: null, updatedAt: now});
        }
        next.updatedAt = now;
        tx.set(db.doc(`requests/${id}`), next);
        return envelope({request: wireRecord(id, next)});
      }});
  }
  return {setHelperAvailability, createRequest, assignRequest, transitionRequest};
}

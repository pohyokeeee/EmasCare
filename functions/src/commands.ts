import {createHash} from "node:crypto";
import {Firestore, Transaction, Timestamp} from "firebase-admin/firestore";
import {Actor, loadActor} from "./auth";
import {fail} from "./errors";
import {stringField} from "./validation";

// Tuple encoding avoids ambiguous concatenations in IDs. Never use caller keys
// for completion/reward identity; later stages will use canonical participation.
export function tupleId(...parts: string[]): string {
  return createHash("sha256").update(JSON.stringify(parts)).digest("hex");
}

function canonical(value: unknown): string {
  if (value === null || typeof value === "string" || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "number" && Number.isFinite(value)) return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype) {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical((value as Record<string, unknown>)[key])}`).join(",")}}`;
  }
  fail("invalid-argument", "INVALID_PAYLOAD");
}

export function payloadHash(payload: unknown): string {
  return createHash("sha256").update(canonical(payload)).digest("hex");
}

interface Command<T, Access> {
  db: Firestore;
  uid: string;
  name: string;
  key: string;
  payload: Record<string, unknown>;
  // Must only read. Runs before the receipt lookup even on a successful retry.
  authorize: (tx: Transaction, actor: Actor) => Promise<Access>;
  // Do all reads before writes; callbacks may run again on transaction conflicts.
  execute: (tx: Transaction, actor: Actor, access: Access) => Promise<T>;
}

export async function runCommand<T, Access = void>(command: Command<T, Access>): Promise<T> {
  const {db, uid, name, key, payload, authorize, execute} = command;
  stringField(key, "INVALID_IDEMPOTENCY_KEY", 128);
  const hash = payloadHash(payload);
  const ref = db.doc(`commandReceipts/${tupleId(uid, name, key)}`);
  return db.runTransaction(async (tx) => {
    const actor = await loadActor(db, uid, tx);
    const access = await authorize(tx, actor);
    const receipt = await tx.get(ref);
    if (receipt.exists) {
      const saved = receipt.data()!;
      if (saved.payloadHash !== hash) fail("already-exists", "IDEMPOTENCY_KEY_REUSED");
      return saved.result as T;
    }
    const result = await execute(tx, actor, access);
    tx.create(ref, {actorUid: uid, functionName: name, payloadHash: hash, result, createdAt: Timestamp.now()});
    return result;
  });
}

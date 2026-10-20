import {fail} from "./errors";

export function inputObject(value: unknown, businessKeys: readonly string[], mutation = false): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    fail("invalid-argument", "INVALID_PAYLOAD");
  }
  const input = value as Record<string, unknown>;
  if (input.contractVersion !== 1) fail("invalid-argument", "UNSUPPORTED_CONTRACT_VERSION");
  const allowed = new Set(["contractVersion", ...(mutation ? ["idempotencyKey"] : []), ...businessKeys]);
  if (Object.keys(input).some((key) => !allowed.has(key))) fail("invalid-argument", "UNKNOWN_FIELD");
  if (mutation) stringField(input.idempotencyKey, "INVALID_IDEMPOTENCY_KEY", 128);
  return input;
}

export function stringField(value: unknown, reason: string, max = 128): string {
  if (typeof value !== "string" || value.trim().length === 0 || value.length > max) {
    fail("invalid-argument", reason);
  }
  return value;
}

export function documentId(value: unknown): string {
  const id = stringField(value, "INVALID_ID");
  if (!/^[A-Za-z0-9_-]+$/.test(id)) fail("invalid-argument", "INVALID_ID");
  return id;
}

export function envelope<T>(data: T): {contractVersion: 1; data: T} {
  return {contractVersion: 1, data};
}

import {Timestamp} from "firebase-admin/firestore";
import {fail} from "./errors";

export interface Slot {weekday: number; startMinute: number; endMinute: number}
export const taskTiers = {phone_help: 1, walk_with_me: 2, sit_with_me: 2, carry_light_item: 3} as const;
export type Task = keyof typeof taskTiers;
const offset = 8 * 3600000;

export function slotsInput(value: unknown): Slot[] {
  if (!Array.isArray(value) || value.length > 128) fail("invalid-argument", "INVALID_AVAILABILITY");
  const slots = value.map((item) => {
    if (!item || typeof item !== "object" || Array.isArray(item) ||
        Object.keys(item).some((key) => !["weekday", "startMinute", "endMinute"].includes(key)) ||
        !Number.isInteger(item.weekday) || item.weekday < 1 || item.weekday > 7 ||
        !Number.isInteger(item.startMinute) || !Number.isInteger(item.endMinute) ||
        item.startMinute < 0 || item.endMinute > 1440 || item.startMinute >= item.endMinute) {
      fail("invalid-argument", "INVALID_AVAILABILITY");
    }
    return {weekday: item.weekday, startMinute: item.startMinute, endMinute: item.endMinute};
  }).sort((a, b) => a.weekday - b.weekday || a.startMinute - b.startMinute);
  for (let i = 1; i < slots.length; i++) {
    if (slots[i]!.weekday === slots[i - 1]!.weekday && slots[i]!.startMinute < slots[i - 1]!.endMinute) {
      fail("invalid-argument", "INVALID_AVAILABILITY");
    }
  }
  return slots;
}

export function isoTime(value: unknown): Timestamp {
  if (typeof value !== "string" || value.startsWith("0000-") || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{3})?Z$/.test(value)) {
    fail("invalid-argument", "INVALID_TIME_RANGE");
  }
  const milliseconds = Date.parse(value);
  const normalized = value.includes(".") ? value : value.replace(/Z$/, ".000Z");
  if (!Number.isFinite(milliseconds) || new Date(milliseconds).toISOString() !== normalized ||
      milliseconds % 60000 !== 0) fail("invalid-argument", "INVALID_TIME_RANGE");
  return Timestamp.fromMillis(milliseconds);
}

export function daySegments(start: Timestamp, end: Timestamp) {
  const segments: Array<{localDate: string; weekday: number; startMinute: number; endMinute: number}> = [];
  for (let cursor = start.toMillis() + offset, limit = end.toMillis() + offset; cursor < limit;) {
    const day = Math.floor(cursor / 86400000) * 86400000;
    const next = Math.min(day + 86400000, limit);
    const date = new Date(day);
    segments.push({localDate: date.toISOString().slice(0, 10), weekday: date.getUTCDay() || 7,
      startMinute: (cursor - day) / 60000, endMinute: (next - day) / 60000});
    cursor = next;
  }
  return segments;
}

export function covers(slots: Slot[], start: Timestamp, end: Timestamp): boolean {
  return daySegments(start, end).every((segment) => {
    let cursor = segment.startMinute;
    for (const slot of slots.filter((slot) => slot.weekday === segment.weekday).sort((a, b) => a.startMinute - b.startMinute)) {
      if (slot.startMinute > cursor) break;
      if (slot.endMinute > cursor) cursor = slot.endMinute;
      if (cursor >= segment.endMinute) return true;
    }
    return false;
  });
}

export function wireRecord(id: string, data: Record<string, unknown>): Record<string, unknown> {
  function convert(value: unknown): unknown {
    if (value instanceof Timestamp) return value.toDate().toISOString();
    if (Array.isArray(value)) return value.map(convert);
    if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, convert(item)]));
    return value;
  }
  return {id, ...(convert(data) as Record<string, unknown>)};
}

import {tupleId} from "./commands";

export function activityLockId(activityId: string, elderId: string): string { return tupleId("activity-elder", activityId, elderId); }
export function attendanceId(activityId: string, elderId: string): string { return tupleId("attendance", activityId, elderId); }
export function completionId(activityId: string | null, requestId: string): string {
  return activityId ? tupleId("activity", activityId) : tupleId("help-session", requestId);
}
export function participationId(eventId: string, uid: string): string { return tupleId("participation", eventId, uid); }

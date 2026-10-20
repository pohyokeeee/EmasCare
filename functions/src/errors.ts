import {HttpsError, FunctionsErrorCode} from "firebase-functions/v2/https";

export function fail(code: FunctionsErrorCode, reason: string): never {
  throw new HttpsError(code, reason.replaceAll("_", " "), {reason});
}

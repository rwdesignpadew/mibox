import { randomInt } from "node:crypto";

export function createRoomCode(existingCodes = new Set()) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const code = String(randomInt(0, 1_000_000)).padStart(6, "0");
    if (!existingCodes.has(code)) return code;
  }
  throw new Error("Could not allocate a room code");
}

export function isRoomCode(value) {
  return typeof value === "string" && /^\d{6}$/.test(value);
}


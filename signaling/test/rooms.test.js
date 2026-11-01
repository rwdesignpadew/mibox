import test from "node:test";
import assert from "node:assert/strict";
import { createRoomCode, isRoomCode } from "../src/rooms.js";

test("room code contains exactly six digits", () => {
  const code = createRoomCode();
  assert.match(code, /^\d{6}$/);
});

test("room code does not collide with existing codes", () => {
  const original = createRoomCode();
  const next = createRoomCode(new Set([original]));
  assert.notEqual(next, original);
});

test("room code validation rejects malformed values", () => {
  assert.equal(isRoomCode("123456"), true);
  assert.equal(isRoomCode("12345"), false);
  assert.equal(isRoomCode("abcdef"), false);
  assert.equal(isRoomCode(123456), false);
});

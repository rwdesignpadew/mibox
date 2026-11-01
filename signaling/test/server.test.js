import test from "node:test";
import assert from "node:assert/strict";
import { WebSocket } from "ws";

process.env.PORT = "0";
const { server } = await import("../src/server.js");

function createInbox(socket) {
  const queue = [];
  const waiters = [];
  socket.on("message", (data) => {
    const message = JSON.parse(data.toString());
    const waiter = waiters.shift();
    if (waiter) waiter.resolve(message);
    else queue.push(message);
  });
  socket.on("error", (error) => {
    while (waiters.length) waiters.shift().reject(error);
  });
  return {
    next() {
      if (queue.length) return Promise.resolve(queue.shift());
      return new Promise((resolve, reject) => waiters.push({ resolve, reject }));
    }
  };
}

function openSocket(url) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    socket.once("open", () => resolve(socket));
    socket.once("error", reject);
  });
}

test("receiver and sender join a room and exchange an offer", async (t) => {
  if (!server.listening) await new Promise((resolve) => server.once("listening", resolve));
  const address = server.address();
  const url = `ws://127.0.0.1:${address.port}/signal`;
  const receiver = await openSocket(url);
  const sender = await openSocket(url);
  const receiverInbox = createInbox(receiver);
  const senderInbox = createInbox(sender);
  t.after(() => {
    receiver.close();
    sender.close();
    server.close();
  });

  receiver.send(JSON.stringify({ type: "join", role: "receiver" }));
  const receiverJoined = await receiverInbox.next();
  assert.match(receiverJoined.roomCode, /^\d{6}$/);

  sender.send(JSON.stringify({ type: "join", role: "sender", roomCode: receiverJoined.roomCode }));
  const senderJoined = await senderInbox.next();
  assert.equal(senderJoined.type, "joined");
  await senderInbox.next(); // peer-joined
  await receiverInbox.next(); // peer-joined

  sender.send(JSON.stringify({ type: "offer", sdp: "test-sdp" }));
  assert.deepEqual(await receiverInbox.next(), { type: "offer", sdp: "test-sdp" });
});

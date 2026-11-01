import http from "node:http";
import { WebSocketServer, WebSocket } from "ws";
import { createRoomCode, isRoomCode } from "./rooms.js";

const port = Number(process.env.PORT ?? 8080);
const rooms = new Map();

function send(socket, message) {
  if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(message));
}

function peerFor(room, role) {
  return role === "receiver" ? room.sender : room.receiver;
}

function removeClient(socket) {
  const { roomCode, role } = socket.session ?? {};
  if (!roomCode || !role) return;
  const room = rooms.get(roomCode);
  if (!room || room[role] !== socket) return;

  room[role] = undefined;
  const peer = peerFor(room, role);
  if (peer) send(peer, { type: "peer-left" });
  if (!room.receiver && !room.sender) rooms.delete(roomCode);
}

function join(socket, message) {
  if (message.role !== "receiver" && message.role !== "sender") {
    send(socket, { type: "error", message: "Invalid role" });
    return;
  }

  let roomCode = message.roomCode;
  if (message.role === "receiver" && !roomCode) {
    roomCode = createRoomCode(new Set(rooms.keys()));
  }
  if (!isRoomCode(roomCode)) {
    send(socket, { type: "error", message: "Room code must contain 6 digits" });
    return;
  }

  const room = rooms.get(roomCode) ?? {};
  if (room[message.role] && room[message.role] !== socket) {
    send(socket, { type: "error", message: `${message.role} is already connected` });
    return;
  }

  removeClient(socket);
  room[message.role] = socket;
  rooms.set(roomCode, room);
  socket.session = { roomCode, role: message.role };
  send(socket, { type: "joined", roomCode, role: message.role, peerPresent: Boolean(peerFor(room, message.role)) });

  const peer = peerFor(room, message.role);
  if (peer) {
    send(peer, { type: "peer-joined", role: message.role });
    send(socket, { type: "peer-joined", role: peer.session.role });
  }
}

function handleMessage(socket, data) {
  let message;
  try {
    message = JSON.parse(data.toString());
  } catch {
    send(socket, { type: "error", message: "Message must be valid JSON" });
    return;
  }

  if (message.type === "join") {
    join(socket, message);
    return;
  }

  if (!["offer", "answer", "ice-candidate", "stop"].includes(message.type)) {
    send(socket, { type: "error", message: "Unsupported message type" });
    return;
  }

  const { roomCode, role } = socket.session ?? {};
  const room = rooms.get(roomCode);
  const peer = room && peerFor(room, role);
  if (!peer) {
    send(socket, { type: "error", message: "Peer is not connected" });
    return;
  }
  send(peer, message);
}

const server = http.createServer((request, response) => {
  if (request.url === "/health") {
    response.writeHead(200, { "content-type": "application/json" });
    response.end(JSON.stringify({ ok: true, rooms: rooms.size }));
    return;
  }
  response.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
  response.end("MiBox Screen signaling server\n");
});

const wss = new WebSocketServer({ server, path: "/signal", maxPayload: 64 * 1024 });
wss.on("connection", (socket) => {
  socket.on("message", (data) => handleMessage(socket, data));
  socket.on("close", () => removeClient(socket));
  socket.on("error", () => removeClient(socket));
});

server.listen(port, "0.0.0.0", () => {
  console.log(`MiBox Screen signaling server listening on http://0.0.0.0:${port}`);
});

export { server };


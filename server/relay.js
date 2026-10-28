// Wololo Royale relay: pairs two players by a room code and passes their
// messages to each other. The host's game runs the match; this server only
// forwards (text: commands and lobby messages, binary: snapshots).
//
// Lobby messages (JSON text):
//   -> {"op": "host", "civ": "romans"}           <- {"op": "room", "code": "ABCD"}
//   -> {"op": "join", "code": "ABCD", "civ": ...} <- {"op": "start", "role": "guest"|"host", "civ": <the other's civ>}
//   <- {"op": "error", "message": "..."}          <- {"op": "left"} when the other player disconnects
// After "start", everything else is forwarded to the other player as is.

const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = process.env.PORT || 8080;
const rooms = new Map(); // code -> {host, guest, hostCiv}

const server = http.createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("ok");
});
const wss = new WebSocketServer({ server, maxPayload: 1 << 20 });

function newCode() {
  const letters = "ABCDEFGHJKLMNPQRSTUVWXYZ"; // no I/O, easy to read out
  for (;;) {
    let code = "";
    for (let i = 0; i < 4; i++) code += letters[Math.floor(Math.random() * letters.length)];
    if (!rooms.has(code)) return code;
  }
}

function send(ws, msg) {
  if (ws && ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
}

wss.on("connection", (ws) => {
  ws.room = null;
  ws.isAlive = true;
  ws.on("pong", () => (ws.isAlive = true));
  ws.on("message", (data, isBinary) => {
    const room = ws.room;
    if (room && room.host && room.guest) {
      const other = room.host === ws ? room.guest : room.host;
      if (other.readyState === other.OPEN) other.send(data, { binary: isBinary });
      return;
    }
    if (isBinary) return;
    let msg;
    try {
      msg = JSON.parse(data.toString());
    } catch {
      return;
    }
    if (msg.op === "host" && !ws.room) {
      const code = newCode();
      ws.room = { code, host: ws, guest: null, hostCiv: String(msg.civ || "") };
      rooms.set(code, ws.room);
      send(ws, { op: "room", code });
    } else if (msg.op === "join" && !ws.room) {
      const room = rooms.get(String(msg.code || "").toUpperCase());
      if (!room || room.guest) {
        send(ws, { op: "error", message: room ? "That game is full" : "No game with that code" });
        return;
      }
      room.guest = ws;
      ws.room = room;
      send(room.host, { op: "start", role: "host", civ: String(msg.civ || "") });
      send(ws, { op: "start", role: "guest", civ: room.hostCiv });
    }
  });
  ws.on("close", () => {
    const room = ws.room;
    if (!room) return;
    const other = room.host === ws ? room.guest : room.host;
    send(other, { op: "left" });
    if (other) other.room = null;
    rooms.delete(room.code);
  });
});

// Drop connections that stopped answering (phones going to sleep).
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) {
      ws.terminate();
      continue;
    }
    ws.isAlive = false;
    ws.ping();
  }
}, 15000);

server.listen(PORT, () => console.log(`relay listening on ${PORT}`));

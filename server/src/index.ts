import express from "express";
import cors from "cors";
import http from "http";
import { WebSocketServer, WebSocket } from "ws";
import { v4 as uuid } from "uuid";
import * as fs from "fs";
import * as path from "path";

const app = express();
app.use(cors());
app.use(express.json());

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: "/ws" });

const PORT = parseInt(process.env.PORT || "2567");
const MAX_ROOMS = 20;
const MAX_CLIENTS_PER_ROOM = 4;
const TICK_MS = 200;          // 5 ticks/sec state broadcast
const PREP_DURATION = 300;    // 5分钟备战
const WAVE_COUNT = 5;
const WAVE_DURATION = 180;    // 3分钟每波

// ─── 配置加载 ────────────────────────────────────────────────
const CONFIG_DIR = path.resolve(__dirname, "../../config");

function loadJson(file: string): any {
  try {
    return JSON.parse(fs.readFileSync(path.join(CONFIG_DIR, file), "utf8"));
  } catch {
    console.warn(`[Config] Cannot load ${file}`);
    return null;
  }
}

const wavesConfig  = loadJson("waves.json");
const itemsConfig  = loadJson("items.json");
const weaponsConfig = loadJson("weapons.json");

// ─── 类型 ────────────────────────────────────────────────────
interface PlayerState {
  id: string;
  name: string;
  x: number;
  y: number;
  dir: string;
  health: number;
  hunger: number;
  ammo: number;
  equippedWeapon: string;
  isAlive: boolean;
  floor: number;
}

interface ZombieState {
  id: string;
  x: number;
  y: number;
  health: number;
  floor: number;
  isAlive: boolean;
}

interface ItemState {
  id: string;
  type: string;
  name: string;
  x: number;
  y: number;
  floor: number;
}

type GamePhase = "WAITING" | "PREP" | "WAVE" | "ENDED";

interface RoomState {
  roomId: string;
  phase: GamePhase;
  wave: number;
  countdown: number;
  players: Map<string, PlayerState>;
  zombies: Map<string, ZombieState>;
  items: Map<string, ItemState>;
}

interface ClientInfo {
  ws: WebSocket;
  sessionId: string;
  roomId: string;
  playerId: string;
}

// ─── 全局状态 ────────────────────────────────────────────────
const rooms = new Map<string, RoomState>();
const clients = new Map<string, ClientInfo>();  // sessionId -> ClientInfo
const roomClients = new Map<string, Set<string>>();  // roomId -> Set<sessionId>
const tickTimers = new Map<string, ReturnType<typeof setInterval>>();

// ─── 游戏地图常量 ────────────────────────────────────────────
const MAP_W = 40 * 16;  // 640px
const MAP_H = 30 * 16;  // 480px
const WALL = 16;

function randomPos(floor: number) {
  return {
    x: WALL + Math.random() * (MAP_W - WALL * 2),
    y: WALL + Math.random() * (MAP_H - WALL * 2),
    floor
  };
}

// ─── 房间管理 ────────────────────────────────────────────────
function getOrCreateRoom(): string | null {
  // 找有空位的房间
  for (const [rid, room] of rooms) {
    const clientSet = roomClients.get(rid) || new Set();
    if (clientSet.size < MAX_CLIENTS_PER_ROOM && room.phase !== "ENDED") {
      return rid;
    }
  }
  // 新建房间
  if (rooms.size >= MAX_ROOMS) return null;
  return createRoom();
}

function createRoom(): string {
  const roomId = uuid().slice(0, 8);
  const items = new Map<string, ItemState>();

  // 生成物品
  const itemTypes = ["food_can","medicine_kit","weapon_pistol","ammo_pistol","food_can","medicine_kit","ammo_pistol"];
  for (let i = 0; i < 15; i++) {
    const tid = itemTypes[i % itemTypes.length];
    const id = `item_${i}`;
    const pos = randomPos(Math.floor(i / 5) + 1);
    items.set(id, {
      id, type: tid.split("_")[0], name: tid,
      x: pos.x, y: pos.y, floor: pos.floor
    });
  }

  const room: RoomState = {
    roomId,
    phase: "WAITING",
    wave: 1,
    countdown: PREP_DURATION,
    players: new Map(),
    zombies: new Map(),
    items
  };

  rooms.set(roomId, room);
  roomClients.set(roomId, new Set());
  console.log(`[Room] Created: ${roomId}`);
  return roomId;
}

function destroyRoom(roomId: string) {
  const timer = tickTimers.get(roomId);
  if (timer) clearInterval(timer);
  tickTimers.delete(roomId);
  rooms.delete(roomId);
  roomClients.delete(roomId);
  console.log(`[Room] Destroyed: ${roomId}`);
}

// ─── 游戏逻辑 Tick ───────────────────────────────────────────
function startRoomTick(roomId: string) {
  if (tickTimers.has(roomId)) return;
  let lastTick = Date.now();

  const timer = setInterval(() => {
    const room = rooms.get(roomId);
    if (!room) { clearInterval(timer); return; }

    const now = Date.now();
    const dt = (now - lastTick) / 1000;
    lastTick = now;

    updateRoom(room, dt);
    broadcastState(roomId);
  }, TICK_MS);

  tickTimers.set(roomId, timer);
}

function updateRoom(room: RoomState, dt: number) {
  if (room.phase === "WAITING") {
    if (room.players.size > 0) {
      // 有玩家就倒计时5秒后开始（给单人游玩用）
      room.countdown -= dt;
      if (room.countdown <= PREP_DURATION - 5) {
        room.phase = "PREP";
        room.countdown = PREP_DURATION;
        broadcastEvent(room.roomId, { type: "phaseChange", phase: "PREP", countdown: PREP_DURATION });
      }
    }
    return;
  }

  room.countdown -= dt;

  if (room.phase === "PREP" && room.countdown <= 0) {
    room.phase = "WAVE";
    room.countdown = WAVE_DURATION;
    spawnZombies(room);
    broadcastEvent(room.roomId, { type: "phaseChange", phase: "WAVE", countdown: WAVE_DURATION });
  }

  if (room.phase === "WAVE") {
    updateZombies(room, dt);
    if (room.countdown <= 0 || room.zombies.size === 0) {
      if (room.wave >= WAVE_COUNT) {
        room.phase = "ENDED";
        broadcastEvent(room.roomId, { type: "phaseChange", phase: "ENDED", countdown: 0 });
      } else {
        room.wave++;
        room.phase = "PREP";
        room.countdown = PREP_DURATION;
        broadcastEvent(room.roomId, { type: "phaseChange", phase: "PREP", countdown: PREP_DURATION });
      }
    }
  }

  // 饥饿值每 10 秒 -1
  for (const [, player] of room.players) {
    if (player.isAlive) {
      player.hunger = Math.max(0, player.hunger - dt / 10);
      if (player.hunger <= 0) {
        player.health = Math.max(0, player.health - dt * 0.5);
        if (player.health <= 0) player.isAlive = false;
      }
    }
  }
}

function spawnZombies(room: RoomState) {
  const count = 5 + room.wave * 3;
  for (let i = 0; i < count; i++) {
    const id = `z_${room.wave}_${i}`;
    const pos = randomPos(Math.ceil(Math.random() * 3));
    room.zombies.set(id, {
      id, x: pos.x, y: pos.y,
      health: 50 + room.wave * 10,
      floor: pos.floor, isAlive: true
    });
  }
  console.log(`[Room ${room.roomId}] Wave ${room.wave}: spawned ${count} zombies`);
}

function updateZombies(room: RoomState, dt: number) {
  const SPEED = 40;
  // 找存活玩家
  const alivePlayers = Array.from(room.players.values()).filter(p => p.isAlive);
  if (alivePlayers.length === 0) return;

  for (const [zid, zombie] of room.zombies) {
    if (!zombie.isAlive) continue;

    // 找同楼层最近玩家
    const targets = alivePlayers.filter(p => p.floor === zombie.floor);
    if (targets.length === 0) continue;

    const target = targets.reduce((a, b) => {
      const da = Math.hypot(a.x - zombie.x, a.y - zombie.y);
      const db = Math.hypot(b.x - zombie.x, b.y - zombie.y);
      return da < db ? a : b;
    });

    const dx = target.x - zombie.x;
    const dy = target.y - zombie.y;
    const dist = Math.hypot(dx, dy);

    if (dist < 20) {
      // 近身攻击
      target.health = Math.max(0, target.health - 5 * dt);
      if (target.health <= 0) target.isAlive = false;
    } else {
      zombie.x += (dx / dist) * SPEED * dt;
      zombie.y += (dy / dist) * SPEED * dt;
    }
  }

  // 清除死亡丧尸
  for (const [zid, z] of room.zombies) {
    if (!z.isAlive) room.zombies.delete(zid);
  }
}

// ─── 广播 ────────────────────────────────────────────────────
function serializeState(room: RoomState) {
  return {
    type: "state",
    state: {
      phase: room.phase,
      wave: room.wave,
      countdown: Math.round(room.countdown),
      players: Object.fromEntries(room.players),
      zombies: Object.fromEntries(room.zombies),
      items: Object.fromEntries(room.items)
    }
  };
}

function broadcastState(roomId: string) {
  const room = rooms.get(roomId);
  if (!room) return;
  const msg = JSON.stringify(serializeState(room));
  const sessionIds = roomClients.get(roomId) || new Set();
  for (const sid of sessionIds) {
    const ci = clients.get(sid);
    if (ci?.ws.readyState === WebSocket.OPEN) {
      ci.ws.send(msg);
    }
  }
}

function broadcastEvent(roomId: string, event: object) {
  const msg = JSON.stringify(event);
  const sessionIds = roomClients.get(roomId) || new Set();
  for (const sid of sessionIds) {
    const ci = clients.get(sid);
    if (ci?.ws.readyState === WebSocket.OPEN) {
      ci.ws.send(msg);
    }
  }
}

// ─── WebSocket 处理 ──────────────────────────────────────────
wss.on("connection", (ws, req) => {
  const urlParams = new URL(req.url || "", `http://localhost`).searchParams;
  const sessionId = urlParams.get("sessionId") || "";
  const roomId    = urlParams.get("roomId") || "";
  const playerName = urlParams.get("playerName") || "Player";

  console.log(`[WS] Connect attempt: sessionId=${sessionId} roomId=${roomId}`);

  const room = rooms.get(roomId);
  if (!room) {
    ws.send(JSON.stringify({ type: "error", message: "Room not found" }));
    ws.close();
    return;
  }

  // 验证 sessionId 或新建玩家
  let playerId = sessionId;
  if (!room.players.has(playerId)) {
    const pos = randomPos(1);
    room.players.set(playerId, {
      id: playerId, name: playerName,
      x: pos.x, y: pos.y,
      dir: "down", health: 100, hunger: 100,
      ammo: 0, equippedWeapon: "none",
      isAlive: true, floor: 1
    });
    console.log(`[Room ${roomId}] Player joined: ${playerName} (${playerId})`);
  }

  const ci: ClientInfo = { ws, sessionId, roomId, playerId };
  clients.set(sessionId, ci);
  const cs = roomClients.get(roomId) || new Set();
  cs.add(sessionId);
  roomClients.set(roomId, cs);

  // 发送初始状态
  ws.send(JSON.stringify(serializeState(room)));

  // 广播玩家加入
  const player = room.players.get(playerId)!;
  broadcastEvent(roomId, { type: "playerJoined", id: playerId, data: player });

  // 消息处理
  ws.on("message", (data) => {
    try {
      const msg = JSON.parse(data.toString());
      handleMessage(ci, msg, room);
    } catch { /* ignore malformed */ }
  });

  ws.on("close", () => {
    clients.delete(sessionId);
    const cs2 = roomClients.get(roomId);
    if (cs2) { cs2.delete(sessionId); }

    room.players.delete(playerId);
    broadcastEvent(roomId, { type: "playerLeft", id: playerId });
    console.log(`[Room ${roomId}] Player left: ${playerName}`);

    // 房间为空 → 延迟 30s 后销毁
    const remaining = roomClients.get(roomId)?.size || 0;
    if (remaining === 0) {
      setTimeout(() => {
        const cs3 = roomClients.get(roomId);
        if (!cs3 || cs3.size === 0) destroyRoom(roomId);
      }, 30000);
    }
  });

  // 开始房间 tick
  startRoomTick(roomId);
});

function handleMessage(ci: ClientInfo, msg: any, room: RoomState) {
  const player = room.players.get(ci.playerId);
  if (!player || !player.isAlive) return;

  switch (msg.type) {
    case "move":
      player.x = Math.max(WALL, Math.min(MAP_W - WALL, msg.x ?? player.x));
      player.y = Math.max(WALL, Math.min(MAP_H - WALL, msg.y ?? player.y));
      player.dir = msg.dir ?? player.dir;
      break;

    case "shoot": {
      const weaponId = player.equippedWeapon;
      if (weaponId === "none") break;
      if (player.ammo <= 0) {
        ci.ws.send(JSON.stringify({ type: "noAmmo" }));
        break;
      }
      player.ammo--;
      const tx: number = msg.targetX ?? 0;
      const ty: number = msg.targetY ?? 0;
      const dx = tx - player.x;
      const dy = ty - player.y;
      const dist = Math.hypot(dx, dy) || 1;
      const range = 300;
      // 命中检测
      for (const [zid, zombie] of room.zombies) {
        if (!zombie.isAlive || zombie.floor !== player.floor) continue;
        const zd = Math.hypot(zombie.x - player.x, zombie.y - player.y);
        if (zd > range) continue;
        // 简单射线碰撞
        const dot = (zombie.x - player.x) * (dx / dist) + (zombie.y - player.y) * (dy / dist);
        if (dot < 0) continue;
        const closestX = player.x + (dx / dist) * dot;
        const closestY = player.y + (dy / dist) * dot;
        if (Math.hypot(closestX - zombie.x, closestY - zombie.y) < 24) {
          zombie.health -= 40;
          if (zombie.health <= 0) {
            zombie.isAlive = false;
            broadcastEvent(ci.roomId, { type: "zombieDead", zombieId: zid });
          }
        }
      }
      broadcastEvent(ci.roomId, {
        type: "shootFx", fromX: player.x, fromY: player.y,
        dirX: dx / dist, dirY: dy / dist
      });
      break;
    }

    case "pickup": {
      const item = room.items.get(msg.itemId);
      if (!item || item.floor !== player.floor) break;
      const distToItem = Math.hypot(item.x - player.x, item.y - player.y);
      if (distToItem > 64) break;
      // 拾取逻辑
      if (item.type === "food") {
        player.hunger = Math.min(100, player.hunger + 30);
      } else if (item.type === "medicine") {
        player.health = Math.min(100, player.health + 30);
      } else if (item.type === "weapon") {
        player.equippedWeapon = item.name === "weapon_pistol" ? "pistol" : "shotgun";
        player.ammo = player.ammo > 0 ? player.ammo : 12;
      } else if (item.type === "ammo") {
        player.ammo = Math.min(99, player.ammo + 12);
      }
      room.items.delete(msg.itemId);
      ci.ws.send(JSON.stringify({ type: "pickupResult", success: true, itemId: msg.itemId }));
      break;
    }

    case "ping":
      ci.ws.send(JSON.stringify({ type: "pong" }));
      break;
  }
}

// ─── HTTP API ────────────────────────────────────────────────
app.get("/health", (_, res) => {
  res.json({ status: "ok", service: "mall-survival-server", version: "2.0.0",
             rooms: rooms.size, clients: clients.size });
});

app.post("/join", (req, res) => {
  const playerName: string = req.body?.playerName || "Player";
  const requestedRoom: string = req.body?.roomId || "";

  let roomId: string;
  if (requestedRoom && rooms.has(requestedRoom)) {
    const cs = roomClients.get(requestedRoom);
    if (!cs || cs.size >= MAX_CLIENTS_PER_ROOM) {
      res.status(400).json({ error: "Room full" });
      return;
    }
    roomId = requestedRoom;
  } else {
    const rid = getOrCreateRoom();
    if (!rid) { res.status(503).json({ error: "Server full" }); return; }
    roomId = rid;
  }

  const sessionId = uuid().slice(0, 12);
  res.json({ roomId, sessionId, wsUrl: `ws://${req.headers.host}/ws?roomId=${roomId}&sessionId=${sessionId}&playerName=${encodeURIComponent(playerName)}` });
});

app.get("/rooms", (_, res) => {
  const list = Array.from(rooms.values()).map(r => ({
    roomId: r.roomId,
    clients: roomClients.get(r.roomId)?.size || 0,
    maxClients: MAX_CLIENTS_PER_ROOM,
    phase: r.phase,
    wave: r.wave
  })).filter(r => r.phase !== "ENDED");
  res.json({ rooms: list, total: list.length });
});

// ─── 启动 ────────────────────────────────────────────────────
server.listen(PORT, "0.0.0.0", () => {
  console.log("==============================================");
  console.log(` 大楼求生 Game Server v2.0 (Pure WebSocket)`);
  console.log(`  Port: ${PORT}`);
  console.log(`  Health: http://0.0.0.0:${PORT}/health`);
  console.log(`  Join:   POST http://0.0.0.0:${PORT}/join`);
  console.log(`  Rooms:  GET  http://0.0.0.0:${PORT}/rooms`);
  console.log(`  WS:     ws://0.0.0.0:${PORT}/ws`);
  console.log("==============================================");
});

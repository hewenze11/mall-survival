import { Server } from "colyseus";
import { createServer } from "http";
import express from "express";
import cors from "cors";
import { GameRoom } from "./rooms/GameRoom";

const PORT = parseInt(process.env.PORT || "2567", 10);

async function main() {
  const app = express();

  app.use(cors());
  app.use(express.json());

  // Health check endpoint
  app.get("/health", (req, res) => {
    res.json({
      status: "ok",
      service: "mall-survival-server",
      version: "1.0.0",
      timestamp: new Date().toISOString(),
    });
  });

  // Server info endpoint
  app.get("/info", (req, res) => {
    res.json({
      name: "大楼求生 官方服务器",
      version: "1.0.0",
      maxRooms: 20,
      playersPerRoom: 4,
      maxPlayers: 50,
      rooms: ["game"],
      endpoints: {
        websocket: `ws://localhost:${PORT}`,
        health: "/health",
        info: "/info",
        rooms: "/rooms",
        matchmake: "/matchmake/joinOrCreate/game",
      },
    });
  });

  const httpServer = createServer(app);
  const gameServer = new Server({ server: httpServer });

  // Register game room - max 4 players per room, auto-creates new rooms when full
  gameServer.define("game", GameRoom, { maxClients: 4 })
    .enableRealtimeListing();

  // Room list endpoint
  app.get("/rooms", (req, res) => {
    try {
      const allRooms: any[] = [];
      // Colyseus v0.15 stores rooms in transport._server or directly accessible
      const transport = (gameServer as any).transport;
      const roomsMap = (gameServer as any)._rooms
        || (transport && transport._rooms)
        || null;

      if (roomsMap instanceof Map) {
        roomsMap.forEach((room: any) => {
          if (room.roomName === "game" || room.roomId) {
            allRooms.push({
              roomId: room.roomId,
              clients: room.clients ? room.clients.length : 0,
              maxClients: room.maxClients || 4,
              locked: room.locked || false,
              phase: room.state?.phase || room.metadata?.phase || "WAITING",
              wave: room.state?.currentWave || 1,
            });
          }
        });
      }
      res.json({ rooms: allRooms, total: allRooms.length });
    } catch (e: any) {
      console.error("[/rooms] Error:", e.message);
      res.json({ rooms: [], total: 0 });
    }
  });

  await gameServer.listen(PORT);

  console.log("==============================================");
  console.log("  Mall Survival Server Started!");
  console.log(`  Port: ${PORT}`);
  console.log(`  WebSocket: ws://0.0.0.0:${PORT}`);
  console.log(`  Health: http://0.0.0.0:${PORT}/health`);
  console.log(`  Rooms: http://0.0.0.0:${PORT}/rooms`);
  console.log(`  Room capacity: 4 players/room, max 20 rooms`);
  console.log("==============================================");
}

main().catch((err) => {
  console.error("[FATAL] Failed to start server:", err);
  process.exit(1);
});

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
      name: "Mall Survival Game Server",
      version: "1.0.0",
      rooms: ["game"],
      endpoints: {
        websocket: `ws://localhost:${PORT}`,
        health: "/health",
        info: "/info",
        matchmake: "/matchmake/joinOrCreate/game",
      },
    });
  });

  const httpServer = createServer(app);
  const gameServer = new Server({ server: httpServer });

  // Register game room
  gameServer.define("game", GameRoom);

  await gameServer.listen(PORT);

  console.log("==============================================");
  console.log("  Mall Survival Server (M1) Started!");
  console.log(`  Port: ${PORT}`);
  console.log(`  WebSocket: ws://0.0.0.0:${PORT}`);
  console.log(`  Health: http://0.0.0.0:${PORT}/health`);
  console.log(`  Colyseus Monitor: http://0.0.0.0:${PORT}/colyseus`);
  console.log("==============================================");
}

main().catch((err) => {
  console.error("[FATAL] Failed to start server:", err);
  process.exit(1);
});

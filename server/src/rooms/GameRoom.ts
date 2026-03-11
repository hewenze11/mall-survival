import { Room, Client } from "colyseus";
import { GameState } from "../schemas/GameState";
import { Player } from "../schemas/Player";
import { WaveSystem } from "../systems/WaveSystem";
import { FloorSystem } from "../systems/FloorSystem";
import { configLoader } from "../config/ConfigLoader";

interface MoveMessage {
  x: number;
  y: number;
  direction?: string;
}

interface ShootMessage {
  targetX: number;
  targetY: number;
}

export class GameRoom extends Room<GameState> {
  private waveSystem!: WaveSystem;
  private floorSystem!: FloorSystem;
  private gameLoop!: ReturnType<typeof setInterval>;
  private lastTick: number = Date.now();

  onCreate(options: Record<string, unknown>): void {
    console.log(`[GameRoom] Room created: ${this.roomId}`, options);

    // Initialize state
    this.setState(new GameState());

    // Initialize systems
    this.waveSystem = new WaveSystem(this.state);
    this.floorSystem = new FloorSystem();

    // Register message handlers
    this.onMessage("move", (client, message: MoveMessage) => {
      this.handleMove(client, message);
    });

    this.onMessage("shoot", (client, message: ShootMessage) => {
      this.handleShoot(client, message);
    });

    this.onMessage("ready", (client) => {
      console.log(`[GameRoom] Player ${client.sessionId} is ready`);
    });

    // Start game loop at ~60fps
    this.gameLoop = setInterval(() => this.tick(), 16);

    console.log(`[GameRoom] Game loop started. Phase: ${this.state.phase}`);
  }

  onJoin(client: Client, options: Record<string, unknown>): void {
    console.log(`[GameRoom] Player joined: ${client.sessionId}`);

    const playerConfig = configLoader.getPlayerConfig();

    const player = new Player();
    player.id = client.sessionId;
    player.health = playerConfig.health;
    player.speed = playerConfig.speed;
    player.hunger = playerConfig.hunger_max;
    player.isAlive = true;

    // Spawn at floor 1 center
    player.x = 800 + (Math.random() - 0.5) * 200;
    player.y = 450 + (Math.random() - 0.5) * 200;

    this.state.players.set(client.sessionId, player);

    // Register in floor system
    this.floorSystem.registerEntity(client.sessionId, this.state.currentFloor, player.x, player.y);

    // Transition to PREP when first player joins
    if (this.state.phase === "WAITING" && this.state.players.size === 1) {
      this.waveSystem.startPrep();
    }

    console.log(`[GameRoom] Player ${client.sessionId} spawned at (${player.x.toFixed(0)}, ${player.y.toFixed(0)}). Total players: ${this.state.players.size}`);
  }

  onLeave(client: Client, consented: boolean): void {
    console.log(`[GameRoom] Player left: ${client.sessionId}, consented: ${consented}`);

    const player = this.state.players.get(client.sessionId);
    if (player) {
      player.isAlive = false;
    }

    this.floorSystem.removeEntity(client.sessionId);

    // Check if all players are gone
    let anyAlive = false;
    this.state.players.forEach((p: Player) => {
      if (p.isAlive) anyAlive = true;
    });

    if (!anyAlive && this.state.phase !== "ENDED") {
      console.log("[GameRoom] All players left, game ended");
      this.state.phase = "ENDED";
    }
  }

  onDispose(): void {
    console.log(`[GameRoom] Room disposed: ${this.roomId}`);
    if (this.gameLoop) {
      clearInterval(this.gameLoop);
    }
  }

  private tick(): void {
    const now = Date.now();
    const deltaTime = now - this.lastTick;
    this.lastTick = now;

    this.waveSystem.update(deltaTime);
  }

  private handleMove(client: Client, message: MoveMessage): void {
    const player = this.state.players.get(client.sessionId);
    if (!player || !player.isAlive) return;

    // Basic bounds checking (1600x900 map)
    player.x = Math.max(0, Math.min(1600, message.x));
    player.y = Math.max(0, Math.min(900, message.y));

    // Update floor system
    this.floorSystem.updateEntityLocation(client.sessionId, player.x, player.y);
  }

  private handleShoot(client: Client, message: ShootMessage): void {
    const player = this.state.players.get(client.sessionId);
    if (!player || !player.isAlive) return;

    // TODO(M2): Implement bullet/hit detection
    console.log(`[GameRoom] Player ${client.sessionId} shot at (${message.targetX}, ${message.targetY})`);

    // Simple: find closest zombie to target point and deal damage
    let closestZombie = null;
    let closestDist = 100; // hit radius

    this.state.zombies.forEach((zombie) => {
      const dx = zombie.x - message.targetX;
      const dy = zombie.y - message.targetY;
      const dist = Math.sqrt(dx * dx + dy * dy);
      if (dist < closestDist) {
        closestDist = dist;
        closestZombie = zombie;
      }
    });

    if (closestZombie) {
      const z = closestZombie as { id: string; health: number };
      z.health -= 25; // base damage
      console.log(`[GameRoom] Hit zombie ${z.id}, health: ${z.health}`);
      if (z.health <= 0) {
        this.waveSystem.removeZombie(z.id);
        console.log(`[GameRoom] Zombie ${z.id} eliminated`);
      }
    }
  }
}

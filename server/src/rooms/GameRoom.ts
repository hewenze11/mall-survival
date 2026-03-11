import { Room, Client } from "colyseus";
import { GameState } from "../schemas/GameState";
import { Player } from "../schemas/Player";
import { Zombie } from "../schemas/Zombie";
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

interface ChangeFloorMessage {
  targetFloor: number;
}

export class GameRoom extends Room<GameState> {
  private waveSystem!: WaveSystem;
  private floorSystem!: FloorSystem;
  private gameLoop!: ReturnType<typeof setInterval>;
  private lastTick: number = Date.now();

  // 楼层隔离：记录每个 client 当前所在楼层
  private clientFloors: Map<string, number> = new Map();

  // 防止同一实体在同一帧多次触发迁移（冷却 1 秒）
  private migrationCooldown: Map<string, number> = new Map();
  private readonly MIGRATION_COOLDOWN_MS = 1000;

  onCreate(options: Record<string, unknown>): void {
    console.log(`[GameRoom] Room created: ${this.roomId}`, options);

    // Initialize state
    this.setState(new GameState());

    // Initialize systems
    this.waveSystem = new WaveSystem(this.state);
    this.floorSystem = new FloorSystem();

    // Bind room to floor system for broadcasting
    this.floorSystem.setRoom(this);

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

    // 客户端主动请求楼层迁移（服务端验证）
    this.onMessage("change_floor", (client, message: ChangeFloorMessage) => {
      this.handleChangeFloor(client, message);
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
    player.currentFloor = 1;

    // Spawn at floor 1 center
    player.x = 800 + (Math.random() - 0.5) * 200;
    player.y = 450 + (Math.random() - 0.5) * 200;

    this.state.players.set(client.sessionId, player);

    // 楼层隔离：记录该 client 的楼层
    this.clientFloors.set(client.sessionId, 1);

    // Register in floor system
    this.floorSystem.registerEntity(client.sessionId, player.currentFloor, player.x, player.y);

    // Transition to PREP when first player joins
    if (this.state.phase === "WAITING" && this.state.players.size === 1) {
      this.waveSystem.startPrep();
    }

    console.log(`[GameRoom] Player ${client.sessionId} spawned at (${player.x.toFixed(0)}, ${player.y.toFixed(0)}) floor ${player.currentFloor}. Total players: ${this.state.players.size}`);
  }

  onLeave(client: Client, consented: boolean): void {
    console.log(`[GameRoom] Player left: ${client.sessionId}, consented: ${consented}`);

    const player = this.state.players.get(client.sessionId);
    if (player) {
      player.isAlive = false;
    }

    this.floorSystem.removeEntity(client.sessionId);
    this.clientFloors.delete(client.sessionId);
    this.migrationCooldown.delete(client.sessionId);

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

    // 跨层检测：检测所有丧尸是否进入楼梯触发区
    this.checkZombieStairTriggers(now);

    // 跨层检测：检测玩家是否进入楼梯触发区（服务端验证）
    this.checkPlayerStairTriggers(now);
  }

  /**
   * 丧尸楼梯触发检测
   * 丧尸进入楼梯区域 → 自动迁移到相邻楼层继续追击
   */
  private checkZombieStairTriggers(now: number): void {
    this.state.zombies.forEach((zombie: Zombie, zombieId: string) => {
      if (zombie.health <= 0) return;

      // 检查迁移冷却
      const lastMigration = this.migrationCooldown.get(zombieId) ?? 0;
      if (now - lastMigration < this.MIGRATION_COOLDOWN_MS) return;

      const stairCheck = this.floorSystem.isInStairZone(zombie.x, zombie.y, zombie.currentFloor);
      if (stairCheck.triggered) {
        const fromFloor = zombie.currentFloor;
        const toFloor = stairCheck.targetFloor;

        console.log(`[GameRoom] Zombie ${zombieId} triggered stair: floor ${fromFloor} → ${toFloor}`);

        // 设置冷却，防止本帧多次触发
        this.migrationCooldown.set(zombieId, now);

        // 执行迁移
        this.floorSystem.migrateEntity(zombieId, fromFloor, toFloor, this.state);

        // 迁移后重新寻找同楼层的追击目标
        this.retargetZombieAfterMigration(zombieId, zombie, toFloor);
      }
    });
  }

  /**
   * 玩家楼梯触发检测（服务端验证）
   */
  private checkPlayerStairTriggers(now: number): void {
    this.state.players.forEach((player: Player, playerId: string) => {
      if (!player.isAlive) return;

      // 检查迁移冷却
      const lastMigration = this.migrationCooldown.get(playerId) ?? 0;
      if (now - lastMigration < this.MIGRATION_COOLDOWN_MS) return;

      const stairCheck = this.floorSystem.isInStairZone(player.x, player.y, player.currentFloor);
      if (stairCheck.triggered) {
        const fromFloor = player.currentFloor;
        const toFloor = stairCheck.targetFloor;

        console.log(`[GameRoom] Player ${playerId} triggered stair: floor ${fromFloor} → ${toFloor}`);

        this.migrationCooldown.set(playerId, now);

        // 执行迁移
        this.floorSystem.migrateEntity(playerId, fromFloor, toFloor, this.state);

        // 更新楼层隔离记录
        this.clientFloors.set(playerId, toFloor);
      }
    });
  }

  /**
   * 丧尸迁移后重新寻找同楼层的追击目标
   */
  private retargetZombieAfterMigration(zombieId: string, zombie: Zombie, newFloor: number): void {
    // 找到同楼层的存活玩家
    const playersOnFloor: Player[] = [];
    this.state.players.forEach((player: Player) => {
      if (player.isAlive && player.currentFloor === newFloor) {
        playersOnFloor.push(player);
      }
    });

    if (playersOnFloor.length > 0) {
      // 优先保持原来的追击目标（如果目标也在新楼层）
      const currentTarget = this.state.players.get(zombie.targetPlayerId);
      if (currentTarget && currentTarget.isAlive && currentTarget.currentFloor === newFloor) {
        // 继续追击原目标
        console.log(`[GameRoom] Zombie ${zombieId} continues targeting ${zombie.targetPlayerId} on floor ${newFloor}`);
      } else {
        // 随机选择新楼层的玩家
        const newTarget = playersOnFloor[Math.floor(Math.random() * playersOnFloor.length)];
        zombie.targetPlayerId = newTarget.id;
        console.log(`[GameRoom] Zombie ${zombieId} retargeted to ${newTarget.id} on floor ${newFloor}`);
      }
    } else {
      // 没有玩家在新楼层，清空追击目标
      zombie.targetPlayerId = "";
      console.log(`[GameRoom] Zombie ${zombieId} has no target on floor ${newFloor}`);
    }
  }

  /**
   * 客户端主动请求楼层迁移（服务端验证版本）
   * 验证玩家确实在楼梯触发区才允许切换
   */
  private handleChangeFloor(client: Client, message: ChangeFloorMessage): void {
    const player = this.state.players.get(client.sessionId);
    if (!player || !player.isAlive) return;

    const { targetFloor } = message;

    // 验证玩家是否在楼梯触发区
    const stairCheck = this.floorSystem.isInStairZone(player.x, player.y, player.currentFloor);
    if (!stairCheck.triggered || stairCheck.targetFloor !== targetFloor) {
      console.warn(`[GameRoom] Player ${client.sessionId} tried to change floor without being in stair zone`);
      return;
    }

    const fromFloor = player.currentFloor;
    console.log(`[GameRoom] Player ${client.sessionId} validated floor change: ${fromFloor} → ${targetFloor}`);

    this.migrationCooldown.set(client.sessionId, Date.now());
    this.floorSystem.migrateEntity(client.sessionId, fromFloor, targetFloor, this.state);
    this.clientFloors.set(client.sessionId, targetFloor);
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

    // 只能击中同楼层的丧尸
    const playerFloor = player.currentFloor;
    let closestZombie: Zombie | null = null;
    let closestDist = 100; // hit radius

    this.state.zombies.forEach((zombie: Zombie) => {
      // 楼层隔离：只允许击中同楼层丧尸
      if (zombie.currentFloor !== playerFloor) return;

      const dx = zombie.x - message.targetX;
      const dy = zombie.y - message.targetY;
      const dist = Math.sqrt(dx * dx + dy * dy);
      if (dist < closestDist) {
        closestDist = dist;
        closestZombie = zombie;
      }
    });

    if (closestZombie) {
      const z = closestZombie as Zombie;
      z.health -= 25; // base damage
      console.log(`[GameRoom] Hit zombie ${z.id}, health: ${z.health}`);
      if (z.health <= 0) {
        this.waveSystem.removeZombie(z.id);
        this.floorSystem.removeEntity(z.id);
        this.migrationCooldown.delete(z.id);
        console.log(`[GameRoom] Zombie ${z.id} eliminated`);
      }
    }
  }
}

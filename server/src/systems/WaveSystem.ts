import { GameState } from "../schemas/GameState";
import { Zombie } from "../schemas/Zombie";
import { Player } from "../schemas/Player";
import { configLoader } from "../config/ConfigLoader";

export class WaveSystem {
  private state: GameState;
  private prepTimer: number = 0;
  private spawnTimer: number = 0;
  private zombiesSpawnedThisWave: number = 0;

  // M4: 3-second inter-wave cooldown
  private waveEndTimer: number = 0;
  private isWaitingNextWave: boolean = false;
  private hungerSettledThisWave: boolean = false;

  // M4: per-second broadcast accumulator
  private tickAccumulatorMs: number = 0;

  // M4: broadcast function injected by GameRoom
  private broadcastFn?: (event: string, data: unknown) => void;

  constructor(state: GameState) {
    this.state = state;
    this.prepTimer = configLoader.getPrepTimeSeconds() * 1000; // ms
    this.state.prepTimeRemaining = configLoader.getPrepTimeSeconds();
    console.log(
      `[WaveSystem] Initialized. Prep time: ${configLoader.getPrepTimeSeconds()}s, ` +
      `Total waves: ${configLoader.getTotalWaves()}`
    );
  }

  /** Inject the room broadcast function so WaveSystem can emit events to clients */
  setBroadcast(fn: (event: string, data: unknown) => void): void {
    this.broadcastFn = fn;
  }

  update(deltaTime: number): void {
    switch (this.state.phase) {
      case "WAITING":
        // Transition to PREP is triggered externally by GameRoom.onJoin
        break;

      case "PREP":
        this.updatePrep(deltaTime);
        break;

      case "WAVE":
        this.updateWave(deltaTime);
        break;

      case "ENDED":
        // Game over, no updates
        break;
    }

    // M4: per-second broadcast of wave status
    this.tickAccumulatorMs += deltaTime;
    if (this.tickAccumulatorMs >= 1000) {
      this.tickAccumulatorMs -= 1000;
      this.broadcastWaveStatus();
    }
  }

  private updatePrep(deltaTime: number): void {
    this.prepTimer -= deltaTime;
    this.state.prepTimeRemaining = Math.max(0, Math.ceil(this.prepTimer / 1000));

    if (this.prepTimer <= 0) {
      console.log("[WaveSystem] ⚠️  Prep time ended! Gate has BROKEN — Wave 1 starting!");
      // M4: broadcast gate_broken event
      this.emit("gate_broken", { message: "大门已破裂！丧尸入侵开始！" });
      this.startNextWave();
    }
  }

  private updateWave(deltaTime: number): void {
    const waveConfig = configLoader.getWaveByNumber(this.state.currentWave);
    if (!waveConfig) {
      console.log("[WaveSystem] No wave config found, ending game");
      this.endGame("VICTORY");
      return;
    }

    // Spawn zombies if we haven't spawned all of them
    if (this.zombiesSpawnedThisWave < waveConfig.zombie_count) {
      this.spawnTimer -= deltaTime;
      if (this.spawnTimer <= 0) {
        this.spawnZombie();
        this.spawnTimer = waveConfig.spawn_interval * 1000; // reset timer
      }
    }

    // M4: check if all players are dead
    if (this.state.players.size > 0) {
      let anyAlive = false;
      this.state.players.forEach((p: Player) => { if (p.isAlive) anyAlive = true; });
      if (!anyAlive) {
        console.log("[WaveSystem] 💀 All players dead — game over (DEFEAT)");
        this.endGame("DEFEAT");
        return;
      }
    }

    // Check if all zombies are dead and all have been spawned
    const aliveZombies = this.getAliveZombiesCount();
    const allSpawned = this.zombiesSpawnedThisWave >= waveConfig.zombie_count;

    if (allSpawned && aliveZombies === 0) {
      if (!this.isWaitingNextWave) {
        this.isWaitingNextWave = true;
        this.waveEndTimer = 3000; // M4: 3-second cooldown
        this.hungerSettledThisWave = false;
        console.log(`[WaveSystem] ✅ Wave ${this.state.currentWave} cleared! Waiting 3s before next wave...`);
        this.emit("wave_cleared", {
          wave: this.state.currentWave,
          message: `第 ${this.state.currentWave} 波通关！`,
        });
      }

      // M4: apply hunger decay once when the wave is first cleared
      if (!this.hungerSettledThisWave) {
        this.hungerSettledThisWave = true;
        this.onWaveComplete();
      }

      // Count down the inter-wave cooldown
      this.waveEndTimer -= deltaTime;
      if (this.waveEndTimer <= 0) {
        this.startNextWave();
      }
    }
  }

  private spawnZombie(): void {
    const zombieConfig = configLoader.getZombieConfig();
    const zombie = new Zombie();

    zombie.id = `zombie_${this.state.currentWave}_${this.zombiesSpawnedThisWave}_${Date.now()}`;
    zombie.health = zombieConfig.health;
    zombie.speed = zombieConfig.speed;
    zombie.currentFloor = 1; // always spawn on floor 1

    // M7: Spawn points from floors.json (data-driven)
    const floor1Cfg    = configLoader.getFloorConfig(1);
    const SPAWN_POINTS = floor1Cfg?.zombie_spawn_points ?? [
      { x: 50, y: 250 }, { x: 50, y: 300 }, { x: 50, y: 200 },
      { x: 30, y: 270 }, { x: 70, y: 230 },
    ];
    const basePos = SPAWN_POINTS[Math.floor(Math.random() * SPAWN_POINTS.length)];
    zombie.x = basePos.x + (Math.random() * 40 - 20);
    zombie.y = basePos.y + (Math.random() * 40 - 20);

    // Target a random alive player
    const alivePlayers = this.getAlivePlayers();
    if (alivePlayers.length > 0) {
      zombie.targetPlayerId = alivePlayers[Math.floor(Math.random() * alivePlayers.length)].id;
    }

    this.state.zombies.set(zombie.id, zombie);
    this.zombiesSpawnedThisWave++;

    console.log(
      `[WaveSystem] 🧟 Spawned zombie ${zombie.id} at (${zombie.x.toFixed(0)}, ${zombie.y.toFixed(0)}) ` +
      `(${this.zombiesSpawnedThisWave}/${configLoader.getWaveByNumber(this.state.currentWave)?.zombie_count})`
    );
  }

  private onWaveComplete(): void {
    // M4: Apply hunger decay to all living players
    const hungerDecay = configLoader.getPlayerConfig().hunger_decay_per_wave;
    console.log(`[WaveSystem] 🍽️  Hunger decay: -${hungerDecay} applied to all living players`);
    this.state.players.forEach((player: Player) => {
      if (player.isAlive) {
        player.hunger = Math.max(0, player.hunger - hungerDecay);
        if (player.hunger <= 0) {
          player.isAlive = false;
          console.log(`[WaveSystem] 💀 Player ${player.id} starved to death`);
        } else {
          console.log(`[WaveSystem] Player ${player.id} hunger: ${player.hunger} (decay: -${hungerDecay})`);
        }
      }
    });
  }

  // M4: end game with result broadcast
  private endGame(result: "VICTORY" | "DEFEAT"): void {
    this.state.phase = "ENDED";
    const message = result === "VICTORY"
      ? "🏆 恭喜！你们通关了！"
      : "💀 全员阵亡，游戏结束！";
    console.log(`[WaveSystem] Game ended: ${result}`);
    this.emit("game_over", { result, message });
  }

  private startNextWave(): void {
    const nextWave = this.state.currentWave + 1;
    const waveConfig = configLoader.getWaveByNumber(nextWave);

    if (!waveConfig) {
      // No more waves → victory
      console.log("[WaveSystem] 🏆 All waves completed! VICTORY!");
      this.endGame("VICTORY");
      return;
    }

    this.state.currentWave = nextWave;
    this.state.phase = "WAVE";
    this.zombiesSpawnedThisWave = 0;
    this.spawnTimer = 0; // spawn first zombie immediately
    this.isWaitingNextWave = false;
    this.hungerSettledThisWave = false;

    console.log(
      `[WaveSystem] 🌊 Starting Wave ${nextWave}: ` +
      `${waveConfig.zombie_count} zombies, spawn_interval: ${waveConfig.spawn_interval}s`
    );
    this.emit("wave_start", {
      wave: nextWave,
      zombieCount: waveConfig.zombie_count,
      message: `第 ${nextWave} 波开始！`,
    });
  }

  // M4: per-second wave status broadcast
  private broadcastWaveStatus(): void {
    const waveConfig = configLoader.getWaveByNumber(this.state.currentWave);
    const progress = {
      spawned: this.zombiesSpawnedThisWave,
      total: waveConfig ? waveConfig.zombie_count : 0,
      aliveZombies: this.getAliveZombiesCount(),
    };

    this.emit("wave_status", {
      phase: this.state.phase,
      currentWave: this.state.currentWave,
      prepTimeRemaining: this.state.prepTimeRemaining,
      waveProgress: progress,
    });
  }

  // -------------------------------------------------------------------------
  // Public API for GameRoom
  // -------------------------------------------------------------------------

  startPrep(): void {
    if (this.state.phase === "WAITING") {
      console.log("[WaveSystem] Transitioning WAITING → PREP");
      this.state.phase = "PREP";
      this.prepTimer = configLoader.getPrepTimeSeconds() * 1000;
      this.state.prepTimeRemaining = configLoader.getPrepTimeSeconds();
    }
  }

  removeZombie(zombieId: string): boolean {
    if (this.state.zombies.has(zombieId)) {
      this.state.zombies.delete(zombieId);
      return true;
    }
    return false;
  }

  /** Return current wave progress snapshot */
  getWaveProgress(): { spawned: number; total: number; aliveZombies: number } {
    const waveConfig = configLoader.getWaveByNumber(this.state.currentWave);
    return {
      spawned: this.zombiesSpawnedThisWave,
      total: waveConfig ? waveConfig.zombie_count : 0,
      aliveZombies: this.getAliveZombiesCount(),
    };
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
  private getAliveZombiesCount(): number {
    let count = 0;
    this.state.zombies.forEach((zombie: Zombie) => {
      if (zombie.health > 0) count++;
    });
    return count;
  }

  private getAlivePlayers(): Player[] {
    const players: Player[] = [];
    this.state.players.forEach((player: Player) => {
      if (player.isAlive) players.push(player);
    });
    return players;
  }

  private emit(event: string, data: unknown): void {
    if (this.broadcastFn) {
      this.broadcastFn(event, data);
    }
  }
}

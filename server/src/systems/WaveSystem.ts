import { MapSchema } from "@colyseus/schema";
import { GameState } from "../schemas/GameState";
import { Zombie } from "../schemas/Zombie";
import { Player } from "../schemas/Player";
import { configLoader } from "../config/ConfigLoader";

export class WaveSystem {
  private state: GameState;
  private prepTimer: number = 0;
  private spawnTimer: number = 0;
  private zombiesSpawnedThisWave: number = 0;
  private lastUpdateTime: number = Date.now();

  constructor(state: GameState) {
    this.state = state;
    this.prepTimer = configLoader.getPrepTimeSeconds() * 1000; // ms
    this.state.prepTimeRemaining = configLoader.getPrepTimeSeconds();
    console.log(`[WaveSystem] Initialized. Prep time: ${configLoader.getPrepTimeSeconds()}s`);
  }

  update(deltaTime: number): void {
    switch (this.state.phase) {
      case "WAITING":
        // Stay in WAITING until at least one player joins
        // Transition triggered externally by GameRoom
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
  }

  private updatePrep(deltaTime: number): void {
    this.prepTimer -= deltaTime;
    this.state.prepTimeRemaining = Math.max(0, Math.ceil(this.prepTimer / 1000));

    if (this.prepTimer <= 0) {
      console.log("[WaveSystem] Prep time ended! Starting Wave 1");
      this.startNextWave();
    }
  }

  private updateWave(deltaTime: number): void {
    const waveConfig = configLoader.getWaveByNumber(this.state.currentWave);
    if (!waveConfig) {
      console.log("[WaveSystem] No wave config found, ending game");
      this.state.phase = "ENDED";
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

    // Check if all zombies are dead
    const aliveZombies = this.getAliveZombiesCount();
    const allSpawned = this.zombiesSpawnedThisWave >= waveConfig.zombie_count;

    if (allSpawned && aliveZombies === 0) {
      console.log(`[WaveSystem] Wave ${this.state.currentWave} completed!`);
      this.onWaveComplete();
    }
  }

  private spawnZombie(): void {
    const zombieConfig = configLoader.getZombieConfig();
    const zombie = new Zombie();

    zombie.id = `zombie_${this.state.currentWave}_${this.zombiesSpawnedThisWave}_${Date.now()}`;
    zombie.health = zombieConfig.health;
    zombie.speed = zombieConfig.speed;
    zombie.currentFloor = this.state.currentFloor;

    // Spawn at random edge position
    const spawnPositions = this.getSpawnPositions();
    const pos = spawnPositions[Math.floor(Math.random() * spawnPositions.length)];
    zombie.x = pos.x;
    zombie.y = pos.y;

    // Target a random alive player
    const alivePlayers = this.getAlivePlayers();
    if (alivePlayers.length > 0) {
      zombie.targetPlayerId = alivePlayers[Math.floor(Math.random() * alivePlayers.length)].id;
    }

    this.state.zombies.set(zombie.id, zombie);
    this.zombiesSpawnedThisWave++;

    console.log(`[WaveSystem] Spawned zombie ${zombie.id} (${this.zombiesSpawnedThisWave}/${configLoader.getWaveByNumber(this.state.currentWave)?.zombie_count})`);
  }

  private getSpawnPositions(): { x: number; y: number }[] {
    // Spawn at edges of a 1600x900 map
    return [
      { x: 0, y: Math.random() * 900 },
      { x: 1600, y: Math.random() * 900 },
      { x: Math.random() * 1600, y: 0 },
      { x: Math.random() * 1600, y: 900 },
    ];
  }

  private onWaveComplete(): void {
    // Apply hunger decay to all players
    const hungerDecay = configLoader.getPlayerConfig().hunger_decay_per_wave;
    this.state.players.forEach((player: Player) => {
      if (player.isAlive) {
        player.hunger = Math.max(0, player.hunger - hungerDecay);
        console.log(`[WaveSystem] Player ${player.id} hunger: ${player.hunger} (decay: -${hungerDecay})`);
      }
    });

    // Move to next wave or end game
    const nextWave = this.state.currentWave + 1;
    const nextWaveConfig = configLoader.getWaveByNumber(nextWave);

    if (nextWaveConfig) {
      this.startNextWave();
    } else {
      console.log("[WaveSystem] All waves completed! Game ended.");
      this.state.phase = "ENDED";
    }
  }

  private startNextWave(): void {
    const nextWave = this.state.currentWave + 1;
    const waveConfig = configLoader.getWaveByNumber(nextWave);

    if (!waveConfig) {
      this.state.phase = "ENDED";
      return;
    }

    this.state.currentWave = nextWave;
    this.state.phase = "WAVE";
    this.zombiesSpawnedThisWave = 0;
    this.spawnTimer = 0; // spawn first zombie immediately

    console.log(`[WaveSystem] Starting Wave ${nextWave}: ${waveConfig.zombie_count} zombies, spawn interval: ${waveConfig.spawn_interval}s`);
  }

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

  startPrep(): void {
    if (this.state.phase === "WAITING") {
      console.log("[WaveSystem] Transitioning WAITING -> PREP");
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
}

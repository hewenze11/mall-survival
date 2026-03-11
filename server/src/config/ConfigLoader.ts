import * as fs from "fs";
import * as path from "path";

interface PlayerConfig {
  health: number;
  speed: number;
  hunger_max: number;
  hunger_decay_per_wave: number;
}

interface ZombieConfig {
  health: number;
  speed: number;
  damage: number;
  attack_rate: number;
}

interface EntitiesConfig {
  player: PlayerConfig;
  zombie: ZombieConfig;
}

interface WaveConfig {
  wave: number;
  zombie_count: number;
  spawn_interval: number;
}

interface WavesConfig {
  prep_time_seconds: number;
  waves: WaveConfig[];
}

export class ConfigLoader {
  private entitiesConfig: EntitiesConfig;
  private wavesConfig: WavesConfig;

  constructor() {
    const configDir = path.resolve(__dirname, "../../..","config");

    const entitiesPath = path.join(configDir, "entities.json");
    const wavesPath = path.join(configDir, "waves.json");

    console.log(`[ConfigLoader] Loading entities from: ${entitiesPath}`);
    console.log(`[ConfigLoader] Loading waves from: ${wavesPath}`);

    this.entitiesConfig = JSON.parse(fs.readFileSync(entitiesPath, "utf-8"));
    this.wavesConfig = JSON.parse(fs.readFileSync(wavesPath, "utf-8"));

    console.log(`[ConfigLoader] Loaded ${this.wavesConfig.waves.length} wave configs`);
    console.log(`[ConfigLoader] Player health: ${this.entitiesConfig.player.health}, speed: ${this.entitiesConfig.player.speed}`);
    console.log(`[ConfigLoader] Zombie health: ${this.entitiesConfig.zombie.health}, speed: ${this.entitiesConfig.zombie.speed}`);
  }

  getEntityConfig(type: "player" | "zombie"): PlayerConfig | ZombieConfig {
    if (type === "player") {
      return this.entitiesConfig.player;
    } else if (type === "zombie") {
      return this.entitiesConfig.zombie;
    }
    throw new Error(`Unknown entity type: ${type}`);
  }

  getPlayerConfig(): PlayerConfig {
    return this.entitiesConfig.player;
  }

  getZombieConfig(): ZombieConfig {
    return this.entitiesConfig.zombie;
  }

  getWaveConfig(): WavesConfig {
    return this.wavesConfig;
  }

  getWaveByNumber(waveNumber: number): WaveConfig | undefined {
    return this.wavesConfig.waves.find(w => w.wave === waveNumber);
  }

  getPrepTimeSeconds(): number {
    return this.wavesConfig.prep_time_seconds;
  }

  getTotalWaves(): number {
    return this.wavesConfig.waves.length;
  }
}

// Singleton instance
export const configLoader = new ConfigLoader();

import * as fs from "fs";
import * as path from "path";

// Try multiple config paths for both Docker and local dev
const CONFIG_PATHS = [
  "/app/config",                                    // Docker container
  path.join(__dirname, "../../../config"),          // local dev: server/dist/config/ → root
  path.join(__dirname, "../../config"),             // local dev: server/src/config/ → root
  path.join(process.cwd(), "config"),               // CWD fallback
];

const CONFIG_DIR =
  CONFIG_PATHS.find((p) => fs.existsSync(path.join(p, "entities.json"))) ||
  CONFIG_PATHS[0];

console.log(`[ConfigLoader] Using config dir: ${CONFIG_DIR}`);

function loadJson(filename: string): any {
  const filePath = path.join(CONFIG_DIR, filename);
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf-8"));
  } catch (e) {
    console.error(`[ConfigLoader] Failed to load ${filePath}: ${e}`);
    throw new Error(`Cannot load config: ${filePath}`);
  }
}

// ── Typed interfaces ────────────────────────────────────────────────────────

export interface PlayerConfig {
  health: number;
  speed: number;
  hunger_max: number;
  hunger_decay_per_wave: number;
  pickup_range: number;
  inventory_max: number;
}

export interface ZombieConfig {
  health: number;
  speed: number;
  damage: number;
  attack_rate: number;
  attack_range: number;
}

export interface WaveConfig {
  wave: number;
  zombie_count: number;
  spawn_interval: number;
}

export interface WavesConfig {
  prep_time_seconds: number;
  waves: WaveConfig[];
}

export interface WeaponConfig {
  damage: number;
  ammo_per_shot: number;
  range: number;
  spread: number;
  pellets: number;
  display_name: string;
}

export interface ItemTemplate {
  type: string;
  name: string;
  value: number;
  weight: number;
}

export interface ItemsConfig {
  templates: ItemTemplate[];
  spawn_per_floor_min: number;
  spawn_per_floor_max: number;
}

export interface StairZone {
  x: number;
  y: number;
  width: number;
  height: number;
  leads_to: number;
}

export interface StairExits {
  from_below?: { x: number; y: number };
  from_above?: { x: number; y: number };
}

export interface SpawnPoint {
  x: number;
  y: number;
}

export interface FloorConfig {
  id: number;
  name: string;
  width: number;
  height: number;
  stair_up: StairZone | null;
  stair_down: StairZone | null;
  stair_exits: StairExits;
  zombie_spawn_points: SpawnPoint[];
  item_spawn_points: SpawnPoint[];
}

export interface FloorsConfig {
  floors: FloorConfig[];
}

// ── Lazy-loaded caches ──────────────────────────────────────────────────────
let _entities: { player: PlayerConfig; zombie: ZombieConfig } | null = null;
let _waves: WavesConfig | null = null;
let _weapons: Record<string, WeaponConfig> | null = null;
let _items: ItemsConfig | null = null;
let _floors: FloorsConfig | null = null;

// ── Singleton ConfigLoader ──────────────────────────────────────────────────
export const configLoader = {
  // ── entities ──────────────────────────────────────────────────────────────
  getPlayerConfig(): PlayerConfig {
    if (!_entities) {
      _entities = loadJson("entities.json");
      console.log(`[ConfigLoader] Loaded entities.json`);
    }
    return _entities!.player;
  },

  getZombieConfig(): ZombieConfig {
    if (!_entities) {
      _entities = loadJson("entities.json");
      console.log(`[ConfigLoader] Loaded entities.json`);
    }
    return _entities!.zombie;
  },

  getEntityConfig(type: "player" | "zombie"): PlayerConfig | ZombieConfig {
    return type === "player" ? this.getPlayerConfig() : this.getZombieConfig();
  },

  // ── waves ─────────────────────────────────────────────────────────────────
  getWaveConfig(): WavesConfig {
    if (!_waves) {
      _waves = loadJson("waves.json");
      console.log(`[ConfigLoader] Loaded waves.json (${_waves!.waves.length} waves)`);
    }
    return _waves!;
  },

  getWaveByNumber(waveNumber: number): WaveConfig | undefined {
    return this.getWaveConfig().waves.find((w) => w.wave === waveNumber);
  },

  getPrepTimeSeconds(): number {
    return this.getWaveConfig().prep_time_seconds;
  },

  getTotalWaves(): number {
    return this.getWaveConfig().waves.length;
  },

  // ── weapons ───────────────────────────────────────────────────────────────
  getWeaponConfig(weapon?: string): WeaponConfig | Record<string, WeaponConfig> {
    if (!_weapons) {
      _weapons = loadJson("weapons.json");
      console.log(`[ConfigLoader] Loaded weapons.json`);
    }
    return weapon ? _weapons![weapon] : _weapons!;
  },

  // ── items ─────────────────────────────────────────────────────────────────
  getItemsConfig(): ItemsConfig {
    if (!_items) {
      _items = loadJson("items.json");
      console.log(`[ConfigLoader] Loaded items.json (${_items!.templates.length} templates)`);
    }
    return _items!;
  },

  // ── floors ────────────────────────────────────────────────────────────────
  getFloorsConfig(): FloorsConfig {
    if (!_floors) {
      _floors = loadJson("floors.json");
      console.log(`[ConfigLoader] Loaded floors.json (${_floors!.floors.length} floors)`);
    }
    return _floors!;
  },

  getFloorConfig(floorId: number): FloorConfig | undefined {
    return this.getFloorsConfig().floors.find((f) => f.id === floorId);
  },

  // ── hot-reload ────────────────────────────────────────────────────────────
  /**
   * Clears all cached configs so the next access re-reads from disk.
   * Useful for runtime hot-reload without restarting the server.
   */
  reload(): void {
    _entities = null;
    _waves = null;
    _weapons = null;
    _items = null;
    _floors = null;
    console.log("[ConfigLoader] All caches cleared — configs will reload on next access.");
  },
};

// Legacy class alias so existing code that does `new ConfigLoader()` keeps working.
// New code should use the `configLoader` singleton directly.
export class ConfigLoader {
  getPlayerConfig = () => configLoader.getPlayerConfig();
  getZombieConfig = () => configLoader.getZombieConfig();
  getEntityConfig = (type: "player" | "zombie") => configLoader.getEntityConfig(type);
  getWaveConfig = () => configLoader.getWaveConfig();
  getWaveByNumber = (n: number) => configLoader.getWaveByNumber(n);
  getPrepTimeSeconds = () => configLoader.getPrepTimeSeconds();
  getTotalWaves = () => configLoader.getTotalWaves();
  getWeaponConfig = (w?: string) => configLoader.getWeaponConfig(w);
  getItemsConfig = () => configLoader.getItemsConfig();
  getFloorsConfig = () => configLoader.getFloorsConfig();
  getFloorConfig = (id: number) => configLoader.getFloorConfig(id);
  reload = () => configLoader.reload();
}

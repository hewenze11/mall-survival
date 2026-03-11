/**
 * FloorSystem - 跨层系统（M7 数据驱动重构）
 * 功能：
 *   - 楼梯触发区域检测（从 floors.json 读取矩形区域）
 *   - 实体楼层迁移（zombie/player）
 *   - 广播 floor_change 事件
 *   - 楼层隔离（客户端根据 currentFloor 字段过滤）
 */

import { Room } from "colyseus";
import { GameState } from "../schemas/GameState";
import { configLoader, FloorConfig } from "../config/ConfigLoader";

export interface FloorData {
  floorId: number;
  name: string;
  width: number;
  height: number;
  spawnPoints: { x: number; y: number }[];
  exitPoints: { x: number; y: number; targetFloor: number }[];
}

export interface EntityLocation {
  entityId: string;
  floor: number;
  x: number;
  y: number;
}

export interface FloorChangeEvent {
  entityId: string;
  entityType: "zombie" | "player";
  fromFloor: number;
  toFloor: number;
  newX: number;
  newY: number;
}

export class FloorSystem {
  private entityLocations: Map<string, EntityLocation> = new Map();
  private room: Room | null = null;

  constructor() {
    // FloorSystem no longer initialises hard-coded floor data.
    // All floor info is loaded on-demand from floors.json via configLoader.
    console.log("[FloorSystem] Initialized (data-driven via floors.json)");
  }

  /** 绑定 Room 实例，用于广播事件 */
  setRoom(room: Room): void {
    this.room = room;
  }

  /**
   * 检测实体是否在楼梯触发区域内（M7：从 floors.json 读取）
   * @returns { triggered: boolean, targetFloor: number }
   */
  isInStairZone(x: number, y: number, floor: number): { triggered: boolean; targetFloor: number } {
    const floorCfg = configLoader.getFloorConfig(floor);
    if (!floorCfg) return { triggered: false, targetFloor: floor };

    // 检测上行楼梯
    const up = floorCfg.stair_up;
    if (up && x >= up.x && x <= up.x + up.width && y >= up.y && y <= up.y + up.height) {
      return { triggered: true, targetFloor: up.leads_to };
    }

    // 检测下行楼梯
    const down = floorCfg.stair_down;
    if (down && x >= down.x && x <= down.x + down.width && y >= down.y && y <= down.y + down.height) {
      return { triggered: true, targetFloor: down.leads_to };
    }

    return { triggered: false, targetFloor: floor };
  }

  /**
   * 迁移实体到另一楼层（M7：出口坐标从 floors.json 读取）
   */
  migrateEntity(
    entityId: string,
    fromFloor: number,
    toFloor: number,
    state: GameState
  ): void {
    const targetFloorCfg = configLoader.getFloorConfig(toFloor);
    if (!targetFloorCfg) {
      console.warn(`[FloorSystem] Target floor ${toFloor} not found in floors.json`);
      return;
    }

    // 确定出口方向（上行 → from_below，下行 → from_above）
    const goingUp = toFloor > fromFloor;
    const exits   = targetFloorCfg.stair_exits;
    const exitPt  = goingUp
      ? (exits.from_below ?? { x: 100, y: 100 })
      : (exits.from_above ?? { x: 100, y: 100 });

    const newX = exitPt.x;
    const newY = exitPt.y;

    let entityType: "zombie" | "player" = "zombie";

    const zombie = state.zombies.get(entityId);
    if (zombie) {
      entityType         = "zombie";
      zombie.currentFloor = toFloor;
      zombie.x           = newX;
      zombie.y           = newY;
      console.log(`[FloorSystem] Zombie ${entityId} migrated: floor ${fromFloor} → ${toFloor} at (${newX}, ${newY})`);
    }

    const player = state.players.get(entityId);
    if (player) {
      entityType          = "player";
      player.currentFloor = toFloor;
      player.x            = newX;
      player.y            = newY;
      console.log(`[FloorSystem] Player ${entityId} migrated: floor ${fromFloor} → ${toFloor} at (${newX}, ${newY})`);
    }

    // 更新内部位置追踪
    const loc = this.entityLocations.get(entityId);
    if (loc) {
      loc.floor = toFloor;
      loc.x     = newX;
      loc.y     = newY;
    } else {
      this.entityLocations.set(entityId, { entityId, floor: toFloor, x: newX, y: newY });
    }

    const event: FloorChangeEvent = { entityId, entityType, fromFloor, toFloor, newX, newY };
    if (this.room) {
      this.room.broadcast("floor_change", event);
      console.log(`[FloorSystem] Broadcasted floor_change: ${JSON.stringify(event)}`);
    } else {
      console.warn("[FloorSystem] Room not set, cannot broadcast floor_change");
    }
  }

  // ── Legacy FloorData helpers (kept for backward-compat with GameRoom) ────

  getFloor(floorId: number): FloorData | undefined {
    const cfg = configLoader.getFloorConfig(floorId);
    if (!cfg) return undefined;
    return this._toFloorData(cfg);
  }

  getAllFloors(): FloorData[] {
    return configLoader.getFloorsConfig().floors.map(f => this._toFloorData(f));
  }

  private _toFloorData(cfg: FloorConfig): FloorData {
    const exitPoints: { x: number; y: number; targetFloor: number }[] = [];
    if (cfg.stair_up)   exitPoints.push({ x: cfg.stair_up.x,   y: cfg.stair_up.y,   targetFloor: cfg.stair_up.leads_to });
    if (cfg.stair_down) exitPoints.push({ x: cfg.stair_down.x, y: cfg.stair_down.y, targetFloor: cfg.stair_down.leads_to });
    return {
      floorId:     cfg.id,
      name:        cfg.name,
      width:       cfg.width,
      height:      cfg.height,
      spawnPoints: cfg.zombie_spawn_points,
      exitPoints,
    };
  }

  // ── Entity location tracking ─────────────────────────────────────────────

  registerEntity(entityId: string, floor: number, x: number, y: number): void {
    this.entityLocations.set(entityId, { entityId, floor, x, y });
  }

  updateEntityLocation(entityId: string, x: number, y: number): void {
    const loc = this.entityLocations.get(entityId);
    if (loc) { loc.x = x; loc.y = y; }
  }

  getEntitiesOnFloor(floorId: number): EntityLocation[] {
    return Array.from(this.entityLocations.values()).filter(loc => loc.floor === floorId);
  }

  removeEntity(entityId: string): void {
    this.entityLocations.delete(entityId);
  }

  /**
   * 获取楼梯触发区（供调试/客户端渲染，M7：从 floors.json 动态构建）
   */
  getStairZones(): Record<string, any> {
    const result: Record<string, any> = {};
    configLoader.getFloorsConfig().floors.forEach(f => {
      if (f.stair_up)   result[String(f.id)]          = { ...f.stair_up,   direction: "up" };
      if (f.stair_down) result[`${f.id}_down`]         = { ...f.stair_down, direction: "down" };
    });
    return result;
  }

  getStairExits(): Record<number, { x: number; y: number }> {
    const result: Record<number, { x: number; y: number }> = {};
    configLoader.getFloorsConfig().floors.forEach(f => {
      const exits = f.stair_exits;
      // Use from_below as canonical exit for each floor (arrival from lower floor)
      const pt = exits.from_below ?? exits.from_above;
      if (pt) result[f.id] = pt;
    });
    return result;
  }
}

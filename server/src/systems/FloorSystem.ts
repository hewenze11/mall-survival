/**
 * FloorSystem - 跨层系统（M3完整实现）
 * 功能：
 *   - 楼梯触发区域检测（矩形碰撞）
 *   - 实体楼层迁移（zombie/player）
 *   - 广播 floor_change 事件
 *   - 楼层隔离（客户端根据 currentFloor 字段过滤）
 */

import { Room } from "colyseus";
import { GameState } from "../schemas/GameState";
import { Player } from "../schemas/Player";
import { Zombie } from "../schemas/Zombie";

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

// 每层楼的楼梯触发区（矩形范围）
// key: floorId (上行) 或 `${floorId}_down` (下行)
interface StairZone {
  x: number;
  y: number;
  width: number;
  height: number;
  leadsTo: number;
  direction: "up" | "down";
}

const STAIR_ZONES: Record<string, StairZone> = {
  "1":      { x: 450, y: 450, width: 100, height: 100, leadsTo: 2, direction: "up" },   // 1楼 → 2楼
  "2":      { x: 450, y: 450, width: 100, height: 100, leadsTo: 3, direction: "up" },   // 2楼 → 3楼
  "2_down": { x: 50,  y: 50,  width: 100, height: 100, leadsTo: 1, direction: "down" }, // 2楼 → 1楼
  "3_down": { x: 50,  y: 50,  width: 100, height: 100, leadsTo: 2, direction: "down" }, // 3楼 → 2楼
};

// 各楼层楼梯出口坐标（抵达该楼层时的生成点）
const STAIR_EXITS: Record<number, { x: number; y: number }> = {
  1: { x: 100, y: 100 }, // 从2楼下来到1楼的出口
  2: { x: 100, y: 100 }, // 从1楼上来到2楼的出口
  3: { x: 100, y: 100 }, // 从2楼上来到3楼的出口
};

export interface FloorChangeEvent {
  entityId: string;
  entityType: "zombie" | "player";
  fromFloor: number;
  toFloor: number;
  newX: number;
  newY: number;
}

export class FloorSystem {
  private floors: Map<number, FloorData> = new Map();
  private entityLocations: Map<string, EntityLocation> = new Map();
  private room: Room | null = null;

  constructor() {
    this.initDefaultFloors();
    console.log("[FloorSystem] Initialized with", this.floors.size, "floors");
  }

  /**
   * 绑定 Room 实例，用于广播事件
   */
  setRoom(room: Room): void {
    this.room = room;
  }

  private initDefaultFloors(): void {
    const defaultFloors: FloorData[] = [
      {
        floorId: 1,
        name: "1F - 商场入口",
        width: 1600,
        height: 900,
        spawnPoints: [
          { x: 800, y: 450 },
          { x: 400, y: 300 },
          { x: 1200, y: 600 },
        ],
        exitPoints: [
          { x: 500, y: 500, targetFloor: 2 },
        ],
      },
      {
        floorId: 2,
        name: "2F - 商场主区",
        width: 1600,
        height: 900,
        spawnPoints: [
          { x: 800, y: 450 },
        ],
        exitPoints: [
          { x: 100, y: 100, targetFloor: 1 },
          { x: 500, y: 500, targetFloor: 3 },
        ],
      },
      {
        floorId: 3,
        name: "3F - 顶层/屋顶",
        width: 1600,
        height: 900,
        spawnPoints: [
          { x: 800, y: 450 },
        ],
        exitPoints: [
          { x: 100, y: 100, targetFloor: 2 },
        ],
      },
    ];

    for (const floor of defaultFloors) {
      this.floors.set(floor.floorId, floor);
    }
  }

  /**
   * 检测实体是否在楼梯触发区域内
   * @returns { triggered: boolean, targetFloor: number }
   */
  isInStairZone(x: number, y: number, floor: number): { triggered: boolean; targetFloor: number } {
    // 检测上行楼梯（key = floor number）
    const upKey = String(floor);
    const upZone = STAIR_ZONES[upKey];
    if (upZone) {
      if (
        x >= upZone.x &&
        x <= upZone.x + upZone.width &&
        y >= upZone.y &&
        y <= upZone.y + upZone.height
      ) {
        return { triggered: true, targetFloor: upZone.leadsTo };
      }
    }

    // 检测下行楼梯（key = `${floor}_down`）
    const downKey = `${floor}_down`;
    const downZone = STAIR_ZONES[downKey];
    if (downZone) {
      if (
        x >= downZone.x &&
        x <= downZone.x + downZone.width &&
        y >= downZone.y &&
        y <= downZone.y + downZone.height
      ) {
        return { triggered: true, targetFloor: downZone.leadsTo };
      }
    }

    return { triggered: false, targetFloor: floor };
  }

  /**
   * 迁移实体到另一楼层（完整实现）
   * 1. 从 fromFloor 的实体列表移除
   * 2. 获取 toFloor 的楼梯出口坐标
   * 3. 更新实体的 currentFloor、x、y
   * 4. 加入 toFloor 的实体列表
   * 5. 广播 floor_change 消息给所有客户端
   */
  migrateEntity(
    entityId: string,
    fromFloor: number,
    toFloor: number,
    state: GameState
  ): void {
    // 验证目标楼层存在
    const targetFloorData = this.floors.get(toFloor);
    if (!targetFloorData) {
      console.warn(`[FloorSystem] Target floor ${toFloor} not found`);
      return;
    }

    // 获取出口坐标
    const exitPoint = STAIR_EXITS[toFloor] ?? targetFloorData.spawnPoints[0];
    const newX = exitPoint.x;
    const newY = exitPoint.y;

    // 确定实体类型并更新 Schema 状态
    let entityType: "zombie" | "player" = "zombie";

    // 尝试更新 zombie
    const zombie = state.zombies.get(entityId);
    if (zombie) {
      entityType = "zombie";
      zombie.currentFloor = toFloor;
      zombie.x = newX;
      zombie.y = newY;
      console.log(`[FloorSystem] Zombie ${entityId} migrated: floor ${fromFloor} → ${toFloor} at (${newX}, ${newY})`);
    }

    // 尝试更新 player
    const player = state.players.get(entityId);
    if (player) {
      entityType = "player";
      player.currentFloor = toFloor;
      player.x = newX;
      player.y = newY;
      console.log(`[FloorSystem] Player ${entityId} migrated: floor ${fromFloor} → ${toFloor} at (${newX}, ${newY})`);
    }

    // 更新内部位置追踪
    const loc = this.entityLocations.get(entityId);
    if (loc) {
      loc.floor = toFloor;
      loc.x = newX;
      loc.y = newY;
    } else {
      this.entityLocations.set(entityId, { entityId, floor: toFloor, x: newX, y: newY });
    }

    // 广播 floor_change 事件给所有客户端
    const event: FloorChangeEvent = {
      entityId,
      entityType,
      fromFloor,
      toFloor,
      newX,
      newY,
    };

    if (this.room) {
      this.room.broadcast("floor_change", event);
      console.log(`[FloorSystem] Broadcasted floor_change: ${JSON.stringify(event)}`);
    } else {
      console.warn("[FloorSystem] Room not set, cannot broadcast floor_change");
    }
  }

  /**
   * 获取楼层数据
   */
  getFloor(floorId: number): FloorData | undefined {
    return this.floors.get(floorId);
  }

  /**
   * 获取所有楼层
   */
  getAllFloors(): FloorData[] {
    return Array.from(this.floors.values());
  }

  /**
   * 注册实体位置
   */
  registerEntity(entityId: string, floor: number, x: number, y: number): void {
    this.entityLocations.set(entityId, { entityId, floor, x, y });
  }

  /**
   * 更新实体位置
   */
  updateEntityLocation(entityId: string, x: number, y: number): void {
    const loc = this.entityLocations.get(entityId);
    if (loc) {
      loc.x = x;
      loc.y = y;
    }
  }

  /**
   * 获取特定楼层的实体
   */
  getEntitiesOnFloor(floorId: number): EntityLocation[] {
    return Array.from(this.entityLocations.values()).filter(
      (loc) => loc.floor === floorId
    );
  }

  /**
   * 移除实体
   */
  removeEntity(entityId: string): void {
    this.entityLocations.delete(entityId);
  }

  /**
   * 获取楼梯触发区定义（用于调试/客户端渲染）
   */
  getStairZones(): Record<string, StairZone> {
    return STAIR_ZONES;
  }

  /**
   * 获取楼梯出口定义
   */
  getStairExits(): Record<number, { x: number; y: number }> {
    return STAIR_EXITS;
  }
}

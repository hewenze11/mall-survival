/**
 * FloorSystem - 楼层/跨场景系统骨架
 * M3阶段完整实现，当前为骨架
 */

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

export class FloorSystem {
  private floors: Map<number, FloorData> = new Map();
  private entityLocations: Map<string, EntityLocation> = new Map();

  constructor() {
    // Initialize default floor layouts (骨架数据)
    this.initDefaultFloors();
    console.log("[FloorSystem] Initialized with", this.floors.size, "floors (skeleton)");
  }

  private initDefaultFloors(): void {
    // 大楼楼层结构（M3 阶段完善）
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
          { x: 800, y: 50, targetFloor: 2 },
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
          { x: 800, y: 850, targetFloor: 1 },
          { x: 800, y: 50, targetFloor: 3 },
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
          { x: 800, y: 850, targetFloor: 2 },
        ],
      },
    ];

    for (const floor of defaultFloors) {
      this.floors.set(floor.floorId, floor);
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
   * 迁移实体到另一楼层
   * TODO(M3): 实现完整的楼层迁移逻辑，包括：
   *   - 验证目标楼层存在
   *   - 广播楼层变更事件给相关客户端
   *   - 处理跨楼层的丧尸追踪逻辑
   *   - 触发楼层加载/卸载
   */
  migrateEntity(entityId: string, fromFloor: number, toFloor: number): void {
    const loc = this.entityLocations.get(entityId);
    if (!loc) {
      console.warn(`[FloorSystem] Entity ${entityId} not found for migration`);
      return;
    }

    if (loc.floor !== fromFloor) {
      console.warn(`[FloorSystem] Entity ${entityId} is on floor ${loc.floor}, not ${fromFloor}`);
      return;
    }

    const targetFloor = this.floors.get(toFloor);
    if (!targetFloor) {
      console.warn(`[FloorSystem] Target floor ${toFloor} not found`);
      return;
    }

    const spawnPoint = targetFloor.spawnPoints[0];
    loc.floor = toFloor;
    loc.x = spawnPoint.x;
    loc.y = spawnPoint.y;

    console.log(`[FloorSystem] [STUB] Migrated entity ${entityId}: floor ${fromFloor} -> ${toFloor}`);
    // TODO(M3): Broadcast floor change to clients, handle zombie re-targeting
  }

  /**
   * 移除实体
   */
  removeEntity(entityId: string): void {
    this.entityLocations.delete(entityId);
  }
}

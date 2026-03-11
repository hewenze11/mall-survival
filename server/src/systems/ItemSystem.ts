import { GameState } from "../schemas/GameState";
import { Item } from "../schemas/Item";
import { InventoryItem } from "../schemas/InventoryItem";
import { configLoader, ItemTemplate } from "../config/ConfigLoader";

export class ItemSystem {
  private itemIdCounter = 0;

  /**
   * 游戏开始时在每层生成物资（M7：数据驱动，从 items.json + floors.json 读取）
   */
  spawnInitialItems(state: GameState): void {
    const itemsCfg = configLoader.getItemsConfig();
    const templates  = itemsCfg.templates;
    const minCount   = itemsCfg.spawn_per_floor_min;
    const maxCount   = itemsCfg.spawn_per_floor_max;

    for (let floor = 1; floor <= 3; floor++) {
      // 从 floors.json 读取物资生成点（M7 数据驱动）
      const floorCfg   = configLoader.getFloorConfig(floor);
      const spawnPoints = floorCfg?.item_spawn_points ?? [{ x: 200, y: 200 }];

      const count = minCount + Math.floor(Math.random() * (maxCount - minCount + 1));
      for (let i = 0; i < count; i++) {
        const point    = spawnPoints[i % spawnPoints.length];
        const template = this.weightedRandom(templates);
        const item     = new Item();
        item.id        = `item_${++this.itemIdCounter}`;
        item.type      = template.type;
        item.name      = template.name;
        item.x         = point.x + (Math.random() * 30 - 15);
        item.y         = point.y + (Math.random() * 30 - 15);
        item.floor     = floor;
        item.value     = template.value;
        item.isPickedUp = false;
        state.items.set(item.id, item);
      }
    }
    console.log(`[ItemSystem] Spawned ${state.items.size} items across 3 floors`);
  }

  /**
   * 处理拾取请求（服务端验证距离）
   */
  handlePickup(playerId: string, itemId: string, state: GameState): boolean {
    const player = state.players.get(playerId);
    const item   = state.items.get(itemId);

    if (!player || !item) {
      console.log(`[ItemSystem] Pickup failed: player=${!!player}, item=${!!item}`);
      return false;
    }

    if (item.isPickedUp) {
      console.log(`[ItemSystem] Item ${itemId} already picked up`);
      return false;
    }

    // 楼层验证
    if (item.floor !== player.currentFloor) {
      console.log(`[ItemSystem] Floor mismatch: item on ${item.floor}, player on ${player.currentFloor}`);
      return false;
    }

    // 距离验证（从 entities.json 读取 pickup_range，M7 数据驱动）
    const pickupRange = configLoader.getPlayerConfig().pickup_range ?? 100;
    const dx   = player.x - item.x;
    const dy   = player.y - item.y;
    const dist = Math.sqrt(dx * dx + dy * dy);
    if (dist > pickupRange) {
      console.log(`[ItemSystem] Too far to pick up: dist=${dist.toFixed(1)}`);
      return false;
    }

    // 背包容量检查（从 entities.json 读取 inventory_max，M7 数据驱动）
    const inventoryMax = configLoader.getPlayerConfig().inventory_max ?? 20;
    if (player.inventoryCount >= inventoryMax) {
      console.log(`[ItemSystem] Inventory full for player ${playerId}`);
      return false;
    }

    // 放入背包（同类物品堆叠）
    const key = `${item.type}_${item.name}`;
    if (player.inventory.has(key)) {
      const existing = player.inventory.get(key)!;
      existing.quantity++;
      console.log(`[ItemSystem] Stacked ${item.name} x${existing.quantity} for player ${playerId}`);
    } else {
      const invItem      = new InventoryItem();
      invItem.itemType   = item.type;
      invItem.itemName   = item.name;
      invItem.quantity   = 1;
      invItem.value      = item.value;
      player.inventory.set(key, invItem);
      player.inventoryCount++;
      console.log(`[ItemSystem] Added ${item.name} (${item.type}) to player ${playerId}'s inventory. Count: ${player.inventoryCount}`);
    }

    // 从地图移除
    item.isPickedUp = true;
    state.items.delete(itemId);
    return true;
  }

  /**
   * 处理使用物品
   */
  handleUseItem(playerId: string, itemKey: string, state: GameState): boolean {
    const player = state.players.get(playerId);
    if (!player) return false;

    const invItem = player.inventory.get(itemKey);
    if (!invItem) {
      console.log(`[ItemSystem] Item ${itemKey} not found in player ${playerId}'s inventory`);
      return false;
    }

    switch (invItem.itemType) {
      case "food":
        player.hunger = Math.min(100, player.hunger + invItem.value);
        console.log(`[ItemSystem] Player ${playerId} ate ${invItem.itemName}, hunger: ${player.hunger}`);
        break;
      case "medicine":
        player.health = Math.min(100, player.health + invItem.value);
        console.log(`[ItemSystem] Player ${playerId} used ${invItem.itemName}, health: ${player.health}`);
        break;
      case "weapon":
        player.equippedWeapon = invItem.itemName;
        console.log(`[ItemSystem] Player ${playerId} equipped ${invItem.itemName}`);
        return true; // 武器不消耗
      case "ammo":
        player.ammo += invItem.value;
        console.log(`[ItemSystem] Player ${playerId} loaded ${invItem.itemName}, ammo: ${player.ammo}`);
        break;
      default:
        console.log(`[ItemSystem] Unknown item type: ${invItem.itemType}`);
        return false;
    }

    // 消耗物品
    invItem.quantity--;
    if (invItem.quantity <= 0) {
      player.inventory.delete(itemKey);
      player.inventoryCount--;
    }
    return true;
  }

  /**
   * 加权随机选择物品模板
   */
  private weightedRandom(templates: ItemTemplate[]): ItemTemplate {
    const total = templates.reduce((sum, t) => sum + t.weight, 0);
    let r = Math.random() * total;
    for (const template of templates) {
      r -= template.weight;
      if (r <= 0) return template;
    }
    return templates[0];
  }
}

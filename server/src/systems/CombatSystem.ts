/**
 * CombatSystem - M6 完整战斗系统
 * 功能：
 *   - 玩家射击：弹药消耗、武器伤害差异、霰弹枪散射
 *   - 丧尸受击：血量扣减、死亡移除
 *   - 丧尸 AI 追击：每 tick 向最近同楼层玩家移动
 *   - 丧尸近战攻击：进入 50px 范围按频率造成伤害
 *   - 玩家死亡：health=0 → isAlive=false，广播 player_dead
 */

import { GameState } from '../schemas/GameState';
import { Room } from 'colyseus';

// 武器配置表
const WEAPON_CONFIG: Record<string, { damage: number; ammoPerShot: number; range: number; spread: number; pellets: number }> = {
  none:    { damage: 10, ammoPerShot: 0, range: 200, spread: 0,   pellets: 1 },
  pistol:  { damage: 30, ammoPerShot: 1, range: 300, spread: 0,   pellets: 1 },
  shotgun: { damage: 60, ammoPerShot: 2, range: 200, spread: 0.3, pellets: 3 },
};

export class CombatSystem {
  private room: Room;
  // 丧尸攻击冷却 Map：zombieId → 上次攻击时间戳(ms)
  private zombieAttackTimers: Map<string, number> = new Map();

  constructor(room: Room) {
    this.room = room;
  }

  /**
   * 处理玩家射击请求
   * @param playerId  射击的玩家 sessionId
   * @param targetX   目标点 X（世界坐标）
   * @param targetY   目标点 Y（世界坐标）
   * @param state     当前游戏状态
   */
  handleShoot(playerId: string, targetX: number, targetY: number, state: GameState): void {
    const player = state.players.get(playerId);
    if (!player || !player.isAlive) return;

    const weaponKey = player.equippedWeapon || 'none';
    const weapon = WEAPON_CONFIG[weaponKey] ?? WEAPON_CONFIG['none'];

    // ── 弹药检查（none 武器无需弹药）
    if (weapon.ammoPerShot > 0) {
      if (player.ammo < weapon.ammoPerShot) {
        this.room.clients.find(c => c.sessionId === playerId)?.send('no_ammo', {});
        return;
      }
      player.ammo -= weapon.ammoPerShot;
    }

    // ── 射击方向归一化向量
    const dx = targetX - player.x;
    const dy = targetY - player.y;
    const dist = Math.sqrt(dx * dx + dy * dy);
    const nx = dist > 0 ? dx / dist : 1;
    const ny = dist > 0 ? dy / dist : 0;

    // ── 对每颗弹丸（霰弹枪 3 颗，手枪/徒手 1 颗）
    const hitsThisShot: string[] = [];
    for (let i = 0; i < weapon.pellets; i++) {
      // 霰弹散射：在 ±spread 弧度内随机偏转
      const spreadAngle = (Math.random() - 0.5) * weapon.spread * 2;
      const cosA = Math.cos(spreadAngle);
      const sinA = Math.sin(spreadAngle);
      const pelletNx = nx * cosA - ny * sinA;
      const pelletNy = nx * sinA + ny * cosA;

      // 寻找射线命中的最近丧尸（同楼层，同一次射击不重复命中）
      let closestId: string | null = null;
      let closestProj = weapon.range; // 沿射线方向的最近投影距离

      state.zombies.forEach((zombie, zId) => {
        if (zombie.currentFloor !== player.currentFloor) return;
        if (hitsThisShot.includes(zId)) return; // 该颗弹丸已命中过

        // 计算丧尸相对于玩家的向量
        const zx = zombie.x - player.x;
        const zy = zombie.y - player.y;

        // 沿射线方向的投影（必须在 [0, range] 内）
        const proj = zx * pelletNx + zy * pelletNy;
        if (proj < 0 || proj > weapon.range) return;

        // 垂直射线方向的距离（命中宽度 ≤ 30px）
        const perp = Math.abs(zx * pelletNy - zy * pelletNx);
        if (perp > 30) return;

        if (proj < closestProj) {
          closestProj = proj;
          closestId = zId;
        }
      });

      if (closestId) {
        hitsThisShot.push(closestId);
        this.applyDamageToZombie(closestId, weapon.damage, state);
      }
    }

    // ── 广播射击特效事件（所有客户端渲染枪线特效）
    this.room.broadcast('shoot_fx', {
      shooterId: playerId,
      fromX: player.x,
      fromY: player.y,
      dirX: nx,
      dirY: ny,
      weapon: weaponKey,
      hits: hitsThisShot,
    });
  }

  /**
   * 对丧尸造成伤害（内部调用）
   */
  private applyDamageToZombie(zombieId: string, damage: number, state: GameState): void {
    const zombie = state.zombies.get(zombieId);
    if (!zombie) return;

    zombie.health -= damage;

    if (zombie.health <= 0) {
      // 丧尸死亡：从状态中移除，广播 zombie_dead
      state.zombies.delete(zombieId);
      this.zombieAttackTimers.delete(zombieId);
      this.room.broadcast('zombie_dead', { zombieId });
      console.log(`[CombatSystem] Zombie ${zombieId} killed (overkill: ${-zombie.health})`);
    } else {
      this.room.broadcast('zombie_hit', { zombieId, health: zombie.health });
    }
  }

  /**
   * 更新丧尸 AI（每游戏帧调用）
   * @param deltaMs  距上次调用的毫秒数
   * @param state    当前游戏状态
   */
  updateZombieAI(deltaMs: number, state: GameState): void {
    const ATTACK_RANGE = 50; // 近战攻击范围（px）

    state.zombies.forEach((zombie, zombieId) => {
      if (zombie.health <= 0) return; // 已死亡（理论上不该出现在 map 里，但保险起见）

      // ── 寻找同楼层最近存活玩家
      interface PlayerSnapshot { id: string; x: number; y: number }
      let closestPlayer: PlayerSnapshot | null = null;
      let closestDist = Infinity;

      state.players.forEach(player => {
        if (!player.isAlive) return;
        if (player.currentFloor !== zombie.currentFloor) return;
        const d = Math.hypot(player.x - zombie.x, player.y - zombie.y);
        if (d < closestDist) {
          closestDist = d;
          closestPlayer = { id: player.id, x: player.x, y: player.y } as PlayerSnapshot;
        }
      });

      if (closestPlayer === null) return; // 同楼层无存活玩家，暂停行动
      const target = closestPlayer as PlayerSnapshot;

      // 更新追击目标
      zombie.targetPlayerId = target.id;

      if (closestDist > ATTACK_RANGE) {
        // ── 追击移动（速度单位：px/s）
        const ddx = target.x - zombie.x;
        const ddy = target.y - zombie.y;
        const ddist = Math.hypot(ddx, ddy);
        if (ddist > 0) {
          zombie.x += (ddx / ddist) * zombie.speed * (deltaMs / 1000);
          zombie.y += (ddy / ddist) * zombie.speed * (deltaMs / 1000);
        }
      } else {
        // ── 近战攻击（attack_rate = 1.0 → 每秒 1 次）
        const lastAttack = this.zombieAttackTimers.get(zombieId) ?? 0;
        const now = Date.now();
        if (now - lastAttack >= 1000) {
          this.zombieAttackTimers.set(zombieId, now);
          this.applyDamageToPlayer(target.id, 15, state);
        }
      }
    });
  }

  /**
   * 对玩家造成伤害（内部调用，由丧尸近战攻击触发）
   */
  private applyDamageToPlayer(playerId: string, damage: number, state: GameState): void {
    const player = state.players.get(playerId);
    if (!player || !player.isAlive) return;

    player.health -= damage;
    console.log(`[CombatSystem] Player ${playerId} hit for ${damage}, health: ${Math.max(0, player.health)}`);

    this.room.broadcast('player_hit', { playerId, health: Math.max(0, player.health) });

    if (player.health <= 0) {
      player.health = 0;
      player.isAlive = false;
      this.room.broadcast('player_dead', { playerId });
      console.log(`[CombatSystem] Player ${playerId} died!`);
    }
  }
}

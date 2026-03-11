import { Schema, type } from "@colyseus/schema";

export class Item extends Schema {
  @type("string")
  id: string = "";

  @type("string")
  type: string = ""; // "food" | "weapon" | "ammo" | "medicine"

  @type("string")
  name: string = "";

  @type("number")
  x: number = 0;

  @type("number")
  y: number = 0;

  @type("number")
  floor: number = 1;

  @type("boolean")
  isPickedUp: boolean = false;

  @type("number")
  value: number = 0; // 食物/药物的恢复量，武器的伤害值，子弹的数量
}

import { Schema, type, MapSchema } from "@colyseus/schema";
import { InventoryItem } from "./InventoryItem";

export class Player extends Schema {
  @type("string")
  id: string = "";

  @type("number")
  x: number = 0;

  @type("number")
  y: number = 0;

  @type("number")
  health: number = 100;

  @type("number")
  speed: number = 150;

  @type("number")
  hunger: number = 100;

  @type("boolean")
  isAlive: boolean = true;

  @type("number")
  currentFloor: number = 1;

  // M5: Inventory system
  @type({ map: InventoryItem })
  inventory = new MapSchema<InventoryItem>();

  @type("number")
  inventoryCount: number = 0;

  @type("string")
  equippedWeapon: string = "none"; // "none" | "pistol" | "shotgun"

  @type("number")
  ammo: number = 0;
}

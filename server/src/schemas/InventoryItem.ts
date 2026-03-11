import { Schema, type } from "@colyseus/schema";

export class InventoryItem extends Schema {
  @type("string")
  itemType: string = "";

  @type("string")
  itemName: string = "";

  @type("number")
  quantity: number = 1;

  @type("number")
  value: number = 0;
}

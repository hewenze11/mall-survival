import { Schema, type } from "@colyseus/schema";

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
}

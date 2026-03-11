import { Schema, type } from "@colyseus/schema";

export class Zombie extends Schema {
  @type("string")
  id: string = "";

  @type("number")
  x: number = 0;

  @type("number")
  y: number = 0;

  @type("number")
  health: number = 80;

  @type("number")
  speed: number = 170;

  @type("string")
  targetPlayerId: string = "";

  @type("number")
  currentFloor: number = 1;
}

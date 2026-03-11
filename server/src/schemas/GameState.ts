import { Schema, type, MapSchema } from "@colyseus/schema";
import { Player } from "./Player";
import { Zombie } from "./Zombie";
import { Item } from "./Item";

export class GameState extends Schema {
  @type("string")
  phase: string = "WAITING";

  @type("number")
  currentWave: number = 0;

  @type("number")
  prepTimeRemaining: number = 300;

  @type({ map: Player })
  players = new MapSchema<Player>();

  @type({ map: Zombie })
  zombies = new MapSchema<Zombie>();

  @type("number")
  currentFloor: number = 1;

  @type({ map: Item })
  items = new MapSchema<Item>();
}

extends Node2D

# Game.gd - Main game scene controller
# Manages players, game state, and coordinates with NetworkManager

const PLAYER_SCENE = preload("res://scenes/Player.tscn")
const REMOTE_PLAYER_SCENE_PATH = "res://scenes/Player.tscn"  # Reuse same visual, different script
const ITEM_SPRITE_SCENE = preload("res://scenes/ItemSprite.tscn")

# ============================================================
# Art Assets - Pixel Art Resources
# ============================================================
const PLAYER_TEX_DOWN  = preload("res://assets/characters/player_down.png")
const PLAYER_TEX_UP    = preload("res://assets/characters/player_up.png")
const PLAYER_TEX_LEFT  = preload("res://assets/characters/player_left.png")
const PLAYER_TEX_RIGHT = preload("res://assets/characters/player_right.png")
const ZOMBIE_TEX       = preload("res://assets/characters/zombie.png")
const FLOOR_TEX        = preload("res://assets/tileset/floor.png")
const WALL_TEX         = preload("res://assets/tileset/wall.png")
const MUZZLE_FLASH_TEX = preload("res://assets/fx/muzzle_flash.png")
const BLOOD_HIT_TEX    = preload("res://assets/fx/blood_hit.png")

# Item icon textures (keyed by item type)
const ITEM_ICONS = {
	"food_can":          "res://assets/icons/food_can.png",
	"food_biscuit":      "res://assets/icons/food_biscuit.png",
	"medicine_kit":      "res://assets/icons/medicine_kit.png",
	"medicine_bandage":  "res://assets/icons/medicine_bandage.png",
	"weapon_pistol":     "res://assets/icons/weapon_pistol.png",
	"weapon_shotgun":    "res://assets/icons/weapon_shotgun.png",
	"ammo_pistol":       "res://assets/icons/ammo_pistol.png",
	"ammo_shotgun":      "res://assets/icons/ammo_shotgun.png",
}

var local_player: CharacterBody2D = null
var remote_players: Dictionary = {}  # player_id -> RemotePlayer node
var item_sprites: Dictionary = {}    # item_id -> ItemSprite node

var current_wave: int = 1
var game_phase: String = "PREP"  # "PREP" or "WAVE"
var prep_countdown: float = 300.0  # 5 minutes
var _ping_timer: float = 0.0

# M6: DamageOverlay 引用（受击红屏）
var _damage_overlay: ColorRect = null

@onready var players_container: Node2D = $players_container
@onready var zombies_container: Node2D = $zombies_container
@onready var items_container: Node2D = $items_container
@onready var hud: Node = $HUD
@onready var camera: Camera2D = $Camera2D
@onready var inventory_ui: CanvasLayer = $Inventory


func _ready() -> void:
	print("[Game] Game scene loaded")
	add_to_group("game")
	
	# Connect NetworkManager signals
	NetworkManager.state_updated.connect(_on_state_updated)
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.game_phase_updated.connect(_on_game_phase_updated)
	NetworkManager.disconnected.connect(_on_disconnected)
	
	# M6: 连接战斗系统信号
	NetworkManager.shoot_fx_received.connect(_on_shoot_fx)
	NetworkManager.player_hit_received.connect(_on_player_hit)
	NetworkManager.zombie_hit_received.connect(_on_zombie_hit)
	NetworkManager.zombie_dead_received.connect(_on_zombie_dead)
	NetworkManager.player_dead_received.connect(_on_player_dead)
	NetworkManager.no_ammo_received.connect(_on_no_ammo)
	
	# Spawn local player
	_spawn_local_player()
	
	# Initialize HUD
	if hud:
		hud.add_to_group("hud")
		hud.update_wave(current_wave)
		hud.update_phase(game_phase, prep_countdown)
	
	# Wire inventory close button
	if inventory_ui:
		var close_btn = inventory_ui.get_node_or_null("inventory_panel/VBoxContainer/close_button")
		if close_btn:
			close_btn.pressed.connect(func(): inventory_ui.hide_inventory())
	
	# M6: 初始化受击红屏 Overlay（动态创建，避免修改 .tscn 文件）
	_setup_damage_overlay()


func _process(delta: float) -> void:
	# Update prep countdown timer locally (server will correct it)
	if game_phase == "PREP" and prep_countdown > 0:
		prep_countdown -= delta
		if hud:
			hud.update_phase(game_phase, prep_countdown)
	
	# Ping display update
	_ping_timer += delta
	if _ping_timer >= 2.0:
		_ping_timer = 0.0
		_update_ping_display()


func _input(event: InputEvent) -> void:
	# Tab键在Player.gd和Inventory.gd中均有处理，这里不重复
	pass


func _spawn_local_player() -> void:
	local_player = PLAYER_SCENE.instantiate()
	players_container.add_child(local_player)
	local_player.global_position = Vector2(640, 360)  # Center of map
	
	# Camera follows local player
	camera.reparent(local_player)
	camera.position = Vector2.ZERO
	
	print("[Game] Local player spawned at %s" % local_player.global_position)


func _spawn_remote_player(player_id: String, player_data: Dictionary) -> void:
	# Don't spawn self
	if player_id == NetworkManager.local_player_id:
		return
	
	# Don't duplicate
	if remote_players.has(player_id):
		return
	
	var scene = load(REMOTE_PLAYER_SCENE_PATH)
	var remote = scene.instantiate()
	
	# Override script with RemotePlayer
	var remote_script = load("res://scripts/RemotePlayer.gd")
	remote.set_script(remote_script)
	
	players_container.add_child(remote)
	
	var spawn_pos = Vector2(
		player_data.get("x", randf_range(400, 880)),
		player_data.get("y", randf_range(200, 520))
	)
	var pname = player_data.get("name", "Player_%s" % player_id.left(4))
	
	remote.initialize(player_id, pname, spawn_pos)
	remote_players[player_id] = remote
	
	print("[Game] Remote player joined: %s (%s)" % [pname, player_id])


func _remove_remote_player(player_id: String) -> void:
	if remote_players.has(player_id):
		var node = remote_players[player_id]
		remote_players.erase(player_id)
		node.queue_free()
		print("[Game] Remote player left: %s" % player_id)


# ============================================================
# Item management
# ============================================================

func _sync_items(items: Dictionary) -> void:
	var current_floor = 1  # TODO: get from player state
	
	# Remove items no longer in state
	var to_remove: Array = []
	for item_id in item_sprites:
		if not items.has(item_id):
			to_remove.append(item_id)
	for item_id in to_remove:
		if item_sprites.has(item_id):
			item_sprites[item_id].queue_free()
			item_sprites.erase(item_id)
	
	# Add/update items
	for item_id in items:
		var item_data = items[item_id]
		if typeof(item_data) != TYPE_DICTIONARY:
			continue
		
		var item_floor = item_data.get("floor", 1)
		# Only show items on current floor
		if item_floor != current_floor:
			# Hide if exists on wrong floor
			if item_sprites.has(item_id):
				item_sprites[item_id].visible = false
			continue
		
		if not item_sprites.has(item_id):
			# Spawn new item sprite
			var sprite = ITEM_SPRITE_SCENE.instantiate()
			items_container.add_child(sprite)
			sprite.initialize(
				item_id,
				item_data.get("type", "food"),
				item_data.get("name", "物品"),
				item_data.get("x", 0.0),
				item_data.get("y", 0.0),
				item_floor
			)
			item_sprites[item_id] = sprite
		else:
			# Ensure visible on correct floor
			item_sprites[item_id].visible = true


# ============================================================
# NetworkManager signal handlers
# ============================================================

func _on_state_updated(state: Dictionary) -> void:
	# Sync game metadata
	if state.has("wave"):
		current_wave = state["wave"]
		if hud:
			hud.update_wave(current_wave)
	
	if state.has("phase"):
		game_phase = state["phase"]
	
	if state.has("countdown"):
		prep_countdown = state["countdown"]
	
	# Sync items from state
	if state.has("items") and typeof(state["items"]) == TYPE_DICTIONARY:
		_sync_items(state["items"])
	
	# Sync remote players from full state
	if state.has("players"):
		var players = state["players"]
		if typeof(players) == TYPE_DICTIONARY:
			for pid in players:
				if pid == NetworkManager.local_player_id:
					# Update local player stats from authoritative state
					var pdata = players[pid]
					if local_player and pdata.has("health"):
						local_player.set_health(pdata["health"])
						if hud:
							hud.update_health(pdata["health"])
					if local_player and pdata.has("hunger"):
						local_player.set_hunger(pdata["hunger"])
						if hud:
							hud.update_hunger(pdata["hunger"])
					# Update HUD weapon/ammo display
					if hud:
						var weapon = pdata.get("equippedWeapon", "none")
						var ammo = pdata.get("ammo", 0)
						if hud.has_method("update_weapon"):
							hud.update_weapon(weapon, ammo)
				else:
					if remote_players.has(pid):
						remote_players[pid].update_state(players[pid])
					else:
						_spawn_remote_player(pid, players[pid])


func _on_player_joined(player_id: String, player_data: Dictionary) -> void:
	_spawn_remote_player(player_id, player_data)


func _on_player_left(player_id: String) -> void:
	_remove_remote_player(player_id)


func _on_game_phase_updated(phase: String, countdown: float) -> void:
	game_phase = phase
	prep_countdown = countdown
	
	if phase == "WAVE":
		current_wave += 1
		print("[Game] Wave %d started!" % current_wave)
		if hud:
			hud.update_wave(current_wave)
	
	if hud:
		hud.update_phase(phase, countdown)


func _on_disconnected() -> void:
	print("[Game] Disconnected from server, returning to main menu")
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _update_ping_display() -> void:
	if hud:
		var status = "ONLINE" if NetworkManager.is_connected_to_room() else "OFFLINE"
		hud.update_ping(status)


# ============================================================
# M6: 战斗系统 - 客户端特效
# ============================================================

# 动态创建受击红屏 Overlay（挂在 HUD CanvasLayer 下）
func _setup_damage_overlay() -> void:
	var canvas: CanvasLayer = get_node_or_null("HUD")
	if canvas == null:
		# 没有 HUD CanvasLayer 时，自建一个
		canvas = CanvasLayer.new()
		canvas.name = "HUDOverlay"
		add_child(canvas)
	
	_damage_overlay = ColorRect.new()
	_damage_overlay.name = "DamageOverlay"
	_damage_overlay.anchors_preset = Control.PRESET_FULL_RECT
	_damage_overlay.color = Color(1, 0, 0, 0.0)  # 初始完全透明
	_damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 确保覆盖整个视口
	_damage_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(_damage_overlay)


# 收到 shoot_fx：在世界坐标绘制枪线特效（Line2D）+ 枪口火焰 Sprite
func _on_shoot_fx(data: Dictionary) -> void:
	var from = Vector2(data.get("fromX", 0.0), data.get("fromY", 0.0))
	var dir = Vector2(data.get("dirX", 1.0), data.get("dirY", 0.0))
	var to = from + dir * 300.0
	
	# 弹道线
	var line = Line2D.new()
	line.width = 2.0
	line.default_color = Color.YELLOW
	line.add_point(from)
	line.add_point(to)
	add_child(line)
	
	# 枪口火焰 Sprite（使用真实像素特效贴图）
	var flash = Sprite2D.new()
	flash.texture = MUZZLE_FLASH_TEX
	flash.position = from + dir * 20.0
	flash.rotation = dir.angle()
	flash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(flash)
	
	# 0.1 秒后自动销毁
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(line):
		line.queue_free()
	if is_instance_valid(flash):
		flash.queue_free()


# 收到 player_hit：本地玩家受击时屏幕闪红 + 血迹特效
func _on_player_hit(data: Dictionary) -> void:
	var pid = data.get("playerId", "")
	if pid != NetworkManager.my_session_id:
		# 非本地玩家受击：在受击位置显示血迹 Sprite
		var hit_x = data.get("x", 0.0)
		var hit_y = data.get("y", 0.0)
		var blood = Sprite2D.new()
		blood.texture = BLOOD_HIT_TEX
		blood.position = Vector2(hit_x, hit_y)
		blood.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(blood)
		await get_tree().create_timer(0.4).timeout
		if is_instance_valid(blood):
			blood.queue_free()
		return
	
	# 本地玩家受击：全屏红闪
	if _damage_overlay == null:
		return
	
	_damage_overlay.color = Color(1, 0, 0, 0.5)
	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(_damage_overlay):
		_damage_overlay.color = Color(1, 0, 0, 0.0)


# 收到 zombie_hit：可选 - 丧尸受击闪烁（TODO: 未来扩展）
func _on_zombie_hit(_data: Dictionary) -> void:
	pass  # 留给未来的 Zombie 节点处理


# 收到 zombie_dead：可选 - 播放丧尸死亡特效（TODO: 未来扩展）
func _on_zombie_dead(_zombie_id: String) -> void:
	pass  # 留给未来的 Zombie 节点处理


# 收到 player_dead：本地玩家死亡处理
func _on_player_dead(player_id: String) -> void:
	if player_id == NetworkManager.my_session_id:
		print("[Game] Local player died!")
		# 可在此处显示死亡画面
		if hud and hud.has_method("show_death_screen"):
			hud.show_death_screen()
	else:
		print("[Game] Remote player died: %s" % player_id)


# 收到 no_ammo：弹药不足提示
func _on_no_ammo() -> void:
	print("[Game] No ammo!")
	if hud and hud.has_method("show_no_ammo"):
		hud.show_no_ammo()


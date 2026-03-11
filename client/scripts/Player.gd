extends CharacterBody2D

# Player.gd - Local player controller
# WASD movement, mouse aiming, shooting, and network sync

const SPEED: float = 200.0
const MOVE_SEND_INTERVAL: float = 0.05  # 50ms throttle for network updates

var player_name: String = ""
var health: int = 100
var hunger: int = 100
var equipped_weapon: String = "none"
var ammo: int = 0
var _move_timer: float = 0.0
var _last_sent_pos: Vector2 = Vector2.ZERO
var _camera: Camera2D = null

@onready var name_label: Label = $NameLabel
@onready var direction_indicator: Line2D = $DirectionIndicator


func _ready() -> void:
	player_name = NetworkManager.local_player_name
	name_label.text = player_name
	
	# Find camera in parent scene
	_camera = get_viewport().get_camera_2d()
	
	# Connect damage signal
	NetworkManager.damage_received.connect(_on_damage_received)
	
	print("[Player] Local player ready: %s" % player_name)


func _process(delta: float) -> void:
	_move_timer += delta
	
	# WASD movement using Input.get_vector (Godot 4 style)
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_dir * SPEED
	
	# Mouse aiming - rotate direction indicator toward mouse
	var mouse_pos = get_global_mouse_position()
	var angle_to_mouse = global_position.angle_to_point(mouse_pos)
	rotation = angle_to_mouse + PI / 2.0
	
	move_and_slide()
	
	# Send position update to server (throttled)
	if _move_timer >= MOVE_SEND_INTERVAL:
		_move_timer = 0.0
		_send_position_update(angle_to_mouse)
	
	# Shooting
	if Input.is_action_just_pressed("shoot"):
		_shoot(mouse_pos)
	
	# Keep camera following player
	if _camera:
		_camera.global_position = global_position


func _send_position_update(direction: float) -> void:
	# Only send if position or direction changed significantly
	if global_position.distance_to(_last_sent_pos) < 0.5 and velocity.is_zero_approx():
		return
	
	_last_sent_pos = global_position
	NetworkManager.send_move(global_position.x, global_position.y, direction)


func _shoot(target_world_pos: Vector2) -> void:
	NetworkManager.send_shoot(target_world_pos.x, target_world_pos.y)
	
	# Visual feedback (flash direction indicator yellow briefly)
	direction_indicator.default_color = Color(1, 1, 0, 1)
	await get_tree().create_timer(0.1).timeout
	direction_indicator.default_color = Color(1, 1, 0, 1)


func _on_damage_received(amount: int) -> void:
	health = max(0, health - amount)
	print("[Player] Took %d damage, health now: %d" % [amount, health])
	
	# Flash red to indicate damage
	modulate = Color(1, 0, 0, 1)
	await get_tree().create_timer(0.15).timeout
	modulate = Color(1, 1, 1, 1)
	
	# Update HUD
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.update_health(health)


func set_health(new_health: int) -> void:
	health = new_health


func set_hunger(new_hunger: int) -> void:
	hunger = new_hunger


func set_weapon(weapon_name: String, new_ammo: int) -> void:
	equipped_weapon = weapon_name
	ammo = new_ammo

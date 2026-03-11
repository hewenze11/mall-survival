extends CharacterBody2D

# RemotePlayer.gd - Remote player representation (other players)
# Receives position/state updates from the server via NetworkManager
# Uses interpolation for smooth movement

const LERP_SPEED: float = 12.0

var player_id: String = ""
var player_name: String = ""
var health: int = 100
var _target_position: Vector2 = Vector2.ZERO
var _target_rotation: float = 0.0

@onready var name_label: Label = $NameLabel


func _ready() -> void:
	_target_position = global_position
	modulate = Color(0.4, 1.0, 0.4, 1.0)  # Green tint to distinguish remote players


func _process(delta: float) -> void:
	# Smooth interpolation toward server-reported position
	global_position = global_position.lerp(_target_position, LERP_SPEED * delta)
	rotation = lerp_angle(rotation, _target_rotation, LERP_SPEED * delta)


func initialize(pid: String, pname: String, pos: Vector2) -> void:
	player_id = pid
	player_name = pname
	global_position = pos
	_target_position = pos
	
	if name_label:
		name_label.text = pname


func update_state(state_data: Dictionary) -> void:
	# Update from server state data
	if state_data.has("x") and state_data.has("y"):
		_target_position = Vector2(state_data["x"], state_data["y"])
	
	if state_data.has("direction"):
		_target_rotation = state_data["direction"] + PI / 2.0
	
	if state_data.has("health"):
		health = state_data["health"]
	
	if state_data.has("name") and name_label:
		player_name = state_data["name"]
		name_label.text = player_name

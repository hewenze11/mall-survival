extends Node2D

# ItemSprite.gd - 地图上物资的可视化节点
# 玩家靠近时显示交互提示，按 E 键拾取

const PICKUP_DISTANCE: float = 100.0

var item_id: String = ""
var item_type: String = ""
var item_name: String = ""
var item_floor: int = 1

var _prompt_visible: bool = false

@onready var name_label: Label = $name_label
@onready var prompt_label: Label = $prompt_label
@onready var icon_label: Label = $icon_label


func _ready() -> void:
	if prompt_label:
		prompt_label.visible = false


func initialize(id: String, type: String, name: String, x: float, y: float, floor: int) -> void:
	item_id = id
	item_type = type
	item_name = name
	item_floor = floor
	global_position = Vector2(x, y)
	
	if name_label:
		name_label.text = name
	
	if icon_label:
		icon_label.text = _get_icon(type)


func _process(_delta: float) -> void:
	# 检测本地玩家距离，显示交互提示
	var game = get_tree().get_first_node_in_group("game")
	if not game:
		return
	
	var local_player = game.get("local_player")
	if not local_player or not is_instance_valid(local_player):
		return
	
	var dist = global_position.distance_to(local_player.global_position)
	var in_range = dist <= PICKUP_DISTANCE
	
	if in_range != _prompt_visible:
		_prompt_visible = in_range
		if prompt_label:
			prompt_label.visible = in_range
	
	# E 键拾取
	if in_range and Input.is_action_just_pressed("interact"):
		NetworkManager.send_pickup(item_id)


func _get_icon(type: String) -> String:
	match type:
		"food":     return "🍞"
		"medicine": return "💊"
		"weapon":   return "🔫"
		"ammo":     return "🔴"
	return "📦"

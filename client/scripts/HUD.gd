extends CanvasLayer

# HUD.gd - Heads-Up Display for Mall Survival
# Shows health, hunger, wave number, phase countdown, and weapon info

var _health: int = 100
var _hunger: int = 100
var _wave: int = 1
var _phase: String = "PREP"

@onready var health_label: Label = $HUDContainer/TopBar/health_label
@onready var hunger_label: Label = $HUDContainer/TopBar/hunger_label
@onready var wave_label: Label = $HUDContainer/TopBar/wave_label
@onready var phase_label: Label = $HUDContainer/TopBar/phase_label
@onready var ping_label: Label = $HUDContainer/TopBar/PingLabel
@onready var weapon_label: Label = $HUDContainer/TopBar/weapon_label
@onready var ammo_label: Label = $HUDContainer/TopBar/ammo_label


func _ready() -> void:
	update_health(100)
	update_hunger(100)
	update_wave(1)
	update_phase("PREP", 300.0)
	update_weapon("none", 0)


func update_health(value: int) -> void:
	_health = clamp(value, 0, 100)
	if health_label:
		health_label.text = "❤️ %d" % _health
		if _health <= 25:
			health_label.modulate = Color(1, 0.2, 0.2, 1)
		elif _health <= 50:
			health_label.modulate = Color(1, 0.6, 0.1, 1)
		else:
			health_label.modulate = Color(1, 1, 1, 1)


func update_hunger(value: int) -> void:
	_hunger = clamp(value, 0, 100)
	if hunger_label:
		hunger_label.text = "🍖 %d" % _hunger
		if _hunger <= 25:
			hunger_label.modulate = Color(1, 0.3, 0.1, 1)
		elif _hunger <= 50:
			hunger_label.modulate = Color(1, 0.7, 0.3, 1)
		else:
			hunger_label.modulate = Color(1, 1, 1, 1)


func update_wave(wave_number: int) -> void:
	_wave = wave_number
	if wave_label:
		wave_label.text = "波次: %d" % wave_number


func update_phase(phase: String, countdown: float) -> void:
	_phase = phase
	if phase_label:
		if phase == "PREP":
			var mins = int(countdown) / 60
			var secs = int(countdown) % 60
			phase_label.text = "备战期: %02d:%02d" % [mins, secs]
			phase_label.modulate = Color(0.3, 0.8, 1, 1)
		elif phase == "WAVE":
			phase_label.text = "🔴 战斗中！"
			phase_label.modulate = Color(1, 0.3, 0.3, 1)
		else:
			phase_label.text = phase
			phase_label.modulate = Color(1, 1, 1, 1)


func update_weapon(weapon: String, player_ammo: int) -> void:
	if weapon_label:
		match weapon:
			"pistol":  weapon_label.text = "🔫 手枪"
			"shotgun": weapon_label.text = "💥 霰弹枪"
			_:         weapon_label.text = "🔫 徒手"
	if ammo_label:
		ammo_label.text = "💥 %d" % player_ammo


func update_ping(status: String) -> void:
	if ping_label:
		ping_label.text = status
		if status == "ONLINE":
			ping_label.modulate = Color(0.3, 1, 0.3, 1)
		else:
			ping_label.modulate = Color(1, 0.3, 0.3, 1)


func show_message(text: String, _duration: float = 3.0) -> void:
	print("[HUD] Message: %s" % text)

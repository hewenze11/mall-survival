extends CanvasLayer

@onready var hp_label: Label = $HUDRoot/TopLeft/HP
@onready var hunger_label: Label = $HUDRoot/TopLeft/Hunger
@onready var wave_label: Label = $HUDRoot/TopRight/Wave
@onready var phase_label: Label = $HUDRoot/TopRight/Phase
@onready var weapon_label: Label = $HUDRoot/BottomLeft/Weapon
@onready var floor_label: Label = $HUDRoot/BottomLeft/Floor
@onready var hint_label: Label = $HUDRoot/BottomLeft/Hint

func _ready() -> void:
	add_to_group("hud")

func update_health(v: int) -> void:
	hp_label.text = "❤ %d" % v

func update_hunger(v: int) -> void:
	hunger_label.text = "🍖 %d" % v

func update_wave(w: int) -> void:
	wave_label.text = "波次 %d" % w

func update_phase(p: String, t: float) -> void:
	var mins := int(t) / 60
	var secs := int(t) % 60
	match p:
		"PREP":  phase_label.text = "⏱ 备战 %02d:%02d" % [mins, secs]
		"WAVE":  phase_label.text = "⚔ 战斗中"
		"ENDED": phase_label.text = "💀 结束"
		_:       phase_label.text = p

func update_weapon(w: String, ammo: int) -> void:
	var wn := {"none":"徒手","pistol":"手枪","shotgun":"霰弹枪"}.get(w, w)
	weapon_label.text = "🔫 %s  ×%d" % [wn, ammo]

func update_floor(f: int) -> void:
	floor_label.text = "🏢 %dF" % f

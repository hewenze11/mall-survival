extends Control

@onready var name_input: LineEdit = $Center/Panel/VBox/NameInput
@onready var status_label: Label = $Center/Panel/VBox/Status
@onready var join_btn: Button = $Center/Panel/VBox/JoinBtn
@onready var room_list: VBoxContainer = $Center/Panel/VBox/RoomList

func _ready() -> void:
	NetworkManager.connected.connect(_on_connected)
	NetworkManager.disconnected.connect(_on_disconnected)
	join_btn.pressed.connect(_on_join)
	name_input.text_submitted.connect(func(_t): _on_join())
	name_input.grab_focus()
	_fetch_rooms()

func _fetch_rooms() -> void:
	status_label.text = "正在获取房间列表..."
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(r, code, _h, body):
		http.queue_free()
		_build_room_list(r, code, body)
	)
	http.request("http://104.64.211.23:2567/rooms")

func _build_room_list(r: int, code: int, body: PackedByteArray) -> void:
	for c in room_list.get_children(): c.queue_free()

	var rooms := []
	if r == HTTPRequest.RESULT_SUCCESS and code == 200:
		var j := JSON.new()
		if j.parse(body.get_string_from_utf8()) == OK:
			rooms = j.get_data().get("rooms", [])

	if rooms.is_empty():
		status_label.text = "暂无房间 — 点击新建"
		join_btn.text = "⚔ 新建游戏"
	else:
		status_label.text = "选择房间或新建"
		join_btn.text = "⚔ 新建房间"
		for rm in rooms:
			var c = rm.get("clients", 0)
			var m = rm.get("maxClients", 4)
			var rid = rm.get("roomId", "")
			var phase = rm.get("phase", "WAITING")
			var btn := Button.new()
			btn.text = "🏢 房间 %s  [%d/%d]  %s" % [rid.left(6), c, m, _phase_zh(phase)]
			btn.custom_minimum_size = Vector2(0, 36)
			var cap: String = rid
			btn.pressed.connect(func(): _join_specific(cap))
			room_list.add_child(btn)

func _phase_zh(p: String) -> String:
	match p:
		"WAITING": return "🟢 等待中"
		"PREP":    return "⏱ 备战"
		"WAVE":    return "⚔ 战斗中"
		_:         return p

func _on_join() -> void:
	var n := name_input.text.strip_edges()
	if n.length() < 1: n = "勇者"
	status_label.text = "正在连接..."
	join_btn.disabled = true
	NetworkManager.join_game(n)

func _join_specific(rid: String) -> void:
	var n := name_input.text.strip_edges()
	if n.length() < 1: n = "勇者"
	status_label.text = "正在加入 %s..." % rid.left(6)
	join_btn.disabled = true
	NetworkManager.join_room(rid, n)

func _on_connected() -> void:
	status_label.text = "✅ 连接成功，进入游戏..."
	await get_tree().create_timer(0.3).timeout
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _on_disconnected() -> void:
	join_btn.disabled = false
	status_label.text = "❌ 连接失败，请重试"

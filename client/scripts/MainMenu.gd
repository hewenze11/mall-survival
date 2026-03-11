extends Control

const SERVER_HTTP = "http://104.64.211.23:2567"
const SERVER_WS   = "ws://104.64.211.23:2567"

var _rooms: Array = []

@onready var player_name_input: LineEdit = $CenterContainer/PanelContainer/VBoxContainer/player_name_input
@onready var join_button: Button = $CenterContainer/PanelContainer/VBoxContainer/JoinButton
@onready var status_label: Label = $CenterContainer/PanelContainer/VBoxContainer/StatusLabel
@onready var room_list: VBoxContainer = $CenterContainer/PanelContainer/VBoxContainer/RoomList

func _ready() -> void:
	NetworkManager.connected.connect(_on_connected)
	NetworkManager.disconnected.connect(_on_disconnected)
	player_name_input.grab_focus()
	player_name_input.text_submitted.connect(_on_name_submitted)
	join_button.pressed.connect(_on_join_pressed)
	status_label.text = "正在获取房间列表..."
	_fetch_rooms()

func _fetch_rooms() -> void:
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(res, code, _h, body):
		http.queue_free()
		if res == HTTPRequest.RESULT_SUCCESS and code == 200:
			var j = JSON.new()
			if j.parse(body.get_string_from_utf8()) == OK:
				var data = j.get_data()
				_rooms = data.get("rooms", [])
		_build_room_list()
	)
	http.request("%s/rooms" % SERVER_HTTP)

func _build_room_list() -> void:
	# 清空旧列表
	for c in room_list.get_children():
		c.queue_free()

	if _rooms.is_empty():
		status_label.text = "暂无进行中的房间，直接加入即新建"
		join_button.text = "➕ 新建并加入"
	else:
		status_label.text = "选择房间加入，或新建"
		join_button.text = "➕ 新建房间"
		for room in _rooms:
			var clients = room.get("clients", 0)
			var max_c = room.get("maxClients", 4)
			var room_id = room.get("roomId", "")
			var phase = room.get("phase", "WAITING")
			var btn = Button.new()
			btn.text = "房间 %s  [%d/%d人]  %s" % [room_id.left(6), clients, max_c, _phase_text(phase)]
			btn.custom_minimum_size = Vector2(0, 40)
			var rid_cap = room_id
			btn.pressed.connect(func(): _join_room(rid_cap))
			room_list.add_child(btn)

func _phase_text(p: String) -> String:
	match p:
		"WAITING": return "🟢 等待中"
		"PREP":    return "⏱ 备战中"
		"WAVE":    return "⚔️ 战斗中"
		_:         return p

func _on_join_pressed() -> void:
	_do_join()

func _on_name_submitted(_t: String) -> void:
	_do_join()

func _do_join() -> void:
	var name_text = player_name_input.text.strip_edges()
	if name_text.length() < 2:
		status_label.text = "玩家名至少2个字符"
		status_label.modulate = Color(1, 0.4, 0.4, 1)
		return
	NetworkManager.local_player_name = name_text
	join_button.disabled = true
	status_label.text = "正在连接服务器..."
	status_label.modulate = Color(0.5, 0.8, 1, 1)
	NetworkManager.connect_to_server(SERVER_WS, "game", name_text)

func _join_room(room_id: String) -> void:
	var name_text = player_name_input.text.strip_edges()
	if name_text.length() < 2:
		status_label.text = "请先填写玩家名"
		return
	NetworkManager.local_player_name = name_text
	join_button.disabled = true
	status_label.text = "正在加入房间 %s..." % room_id.left(6)
	status_label.modulate = Color(0.5, 0.8, 1, 1)
	# 加入指定房间
	NetworkManager.connect_to_room_id(SERVER_WS, room_id, name_text)

func _on_connected() -> void:
	status_label.text = "连接成功！进入游戏中..."
	status_label.modulate = Color(0.3, 1, 0.3, 1)
	await get_tree().create_timer(0.3).timeout
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _on_disconnected() -> void:
	join_button.disabled = false
	status_label.text = "连接失败，请重试"
	status_label.modulate = Color(1, 0.4, 0.4, 1)

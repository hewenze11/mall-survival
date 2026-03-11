extends Node

signal connected
signal disconnected
signal state_updated(state: Dictionary)
signal player_joined(player_id: String, player_data: Dictionary)
signal player_left(player_id: String)
signal game_phase_updated(phase: String, countdown: float)
signal damage_received(amount: int)
signal room_error(code: int, message: String)
signal pickup_result(success: bool, item_id: String)
signal use_item_result(success: bool, item_key: String)
signal items_updated(items: Dictionary)
signal shoot_fx_received(data: Dictionary)
signal player_hit_received(data: Dictionary)
signal zombie_hit_received(data: Dictionary)
signal zombie_dead_received(zombie_id: String)
signal player_dead_received(player_id: String)
signal no_ammo_received()

enum ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, IN_ROOM }

var _ws: WebSocketPeer = null
var _state: ConnectionState = ConnectionState.DISCONNECTED
var _session_id: String = ""
var _move_throttle_timer: float = 0.0
const _move_throttle_interval: float = 0.05

var local_player_name: String = ""
var local_player_id: String = ""
var my_session_id: String = ""
var game_state: Dictionary = {}
var _server_url: String = ""
var _room_name: String = ""

func _ready() -> void:
	set_process(true)
	print("[NetworkManager] Initialized")

func _process(delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var ws_state = _ws.get_ready_state()
	match ws_state:
		WebSocketPeer.STATE_OPEN:
			if _state == ConnectionState.CONNECTING:
				_on_ws_open()
			_receive_messages()
		WebSocketPeer.STATE_CLOSED:
			if _state != ConnectionState.DISCONNECTED:
				print("[NetworkManager] WS closed: %d %s" % [_ws.get_close_code(), _ws.get_close_reason()])
				_state = ConnectionState.DISCONNECTED
				disconnected.emit()
	if _move_throttle_timer > 0:
		_move_throttle_timer -= delta

# ── Public API ──────────────────────────────────────────────

func connect_to_server(server_url: String, room_name: String, player_name: String) -> void:
	print("[NetworkManager] Connecting to %s / room=%s as '%s'" % [server_url, room_name, player_name])
	_server_url = server_url
	_room_name  = room_name
	local_player_name = player_name
	_state = ConnectionState.CONNECTING
	_http_matchmake(server_url, room_name, player_name)

func disconnect_from_server() -> void:
	if _ws != null and _state != ConnectionState.DISCONNECTED:
		_ws.close(1000, "bye")
	_state = ConnectionState.DISCONNECTED

func send_move(x: float, y: float, direction: float) -> void:
	if _state != ConnectionState.IN_ROOM or _move_throttle_timer > 0:
		return
	_move_throttle_timer = _move_throttle_interval
	_send_msg({"type":"move","x":snappedf(x,0.1),"y":snappedf(y,0.1),"direction":snappedf(direction,0.01)})

func send_shoot(tx: float, ty: float) -> void:
	if _state != ConnectionState.IN_ROOM: return
	_send_msg({"type":"shoot","targetX":tx,"targetY":ty})

func send_pickup(item_id: String) -> void:
	if _state != ConnectionState.IN_ROOM: return
	_send_msg({"type":"pickup","itemId":item_id})

func send_use_item(item_key: String) -> void:
	if _state != ConnectionState.IN_ROOM: return
	_send_msg({"type":"use_item","itemKey":item_key})

func send_interact() -> void:
	if _state != ConnectionState.IN_ROOM: return
	_send_msg({"type":"interact"})

func is_connected_to_room() -> bool:
	return _state == ConnectionState.IN_ROOM

# ── Matchmaker (HTTP → WS two-phase) ────────────────────────

func _http_matchmake(server_url: String, room_name: String, player_name: String) -> void:
	var http_base = server_url.replace("ws://","http://").replace("wss://","https://")
	var url = "%s/matchmake/joinOrCreate/%s" % [http_base, room_name]
	print("[NetworkManager] Matchmaking: POST %s" % url)
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(res, code, _hdrs, body):
		_on_matchmake_done(res, code, body, http))
	var err = http.request(url, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify({"playerName": player_name}))
	if err != OK:
		push_error("[NetworkManager] HTTPRequest failed: %d" % err)
		_state = ConnectionState.DISCONNECTED
		disconnected.emit()

func _on_matchmake_done(result: int, code: int, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	var text = body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_error("[NetworkManager] Matchmake HTTP error %d: %s" % [code, text])
		_state = ConnectionState.DISCONNECTED
		disconnected.emit()
		return
	var json = JSON.new()
	if json.parse(text) != OK:
		push_error("[NetworkManager] Matchmake bad JSON: %s" % text)
		_state = ConnectionState.DISCONNECTED
		disconnected.emit()
		return
	var data = json.get_data()
	print("[NetworkManager] Matchmake OK: %s" % text.left(300))
	var session_id = data.get("sessionId","")
	var room_id    = data.get("room",{}).get("roomId","")
	if session_id.is_empty() or room_id.is_empty():
		push_error("[NetworkManager] Missing sessionId/roomId")
		_state = ConnectionState.DISCONNECTED
		disconnected.emit()
		return
	_session_id    = session_id
	local_player_id = session_id
	my_session_id  = session_id
	var ws_url = "%s/%s?sessionId=%s" % [_server_url, room_id, session_id]
	print("[NetworkManager] WS connecting: %s" % ws_url)
	_ws = WebSocketPeer.new()
	_ws.supported_protocols = PackedStringArray(["binary"])
	if _ws.connect_to_url(ws_url) != OK:
		push_error("[NetworkManager] WS connect failed")
		_state = ConnectionState.DISCONNECTED
		disconnected.emit()

# ── WebSocket ────────────────────────────────────────────────

func _on_ws_open() -> void:
	print("[NetworkManager] WS open → IN_ROOM")
	_state = ConnectionState.IN_ROOM
	connected.emit()

func _receive_messages() -> void:
	while _ws.get_available_packet_count() > 0:
		var pkt = _ws.get_packet()
		var txt = pkt.get_string_from_utf8()
		if txt.is_empty(): continue
		var j = JSON.new()
		if j.parse(txt) != OK: continue
		var msg = j.get_data()
		if typeof(msg) == TYPE_DICTIONARY:
			_dispatch(msg)

func _dispatch(msg: Dictionary) -> void:
	var t = msg.get("type","")
	match t:
		"playerJoined":  player_joined.emit(msg.get("id",""), msg.get("player",{}))
		"playerLeft":    player_left.emit(msg.get("id",""))
		"state":         _process_state(msg.get("state", msg))
		"patch":
			var p = msg.get("patch", msg)
			if typeof(p) == TYPE_DICTIONARY:
				for k in p: game_state[k] = p[k]
				state_updated.emit(game_state)
		"wave_status":
			game_phase_updated.emit(msg.get("phase","PREP"), float(msg.get("prepTimeRemaining",0)))
		"damage":        damage_received.emit(int(msg.get("amount",0)))
		"pickup_result": pickup_result.emit(msg.get("success",false), msg.get("itemId",""))
		"use_item_result": use_item_result.emit(msg.get("success",false), msg.get("itemKey",""))
		"shoot_fx":      shoot_fx_received.emit(msg)
		"player_hit":    player_hit_received.emit(msg)
		"zombie_hit":    zombie_hit_received.emit(msg)
		"zombie_dead":   zombie_dead_received.emit(msg.get("zombieId",""))
		"player_dead":   player_dead_received.emit(msg.get("playerId",""))
		"no_ammo":       no_ammo_received.emit()

func _process_state(s: Dictionary) -> void:
	game_state = s
	state_updated.emit(s)
	if s.has("players"):
		var pl = s["players"]
		if typeof(pl) == TYPE_DICTIONARY:
			for pid in pl: player_joined.emit(pid, pl[pid])

func _send_msg(data: Dictionary) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN: return
	_ws.send(JSON.stringify(data).to_utf8_buffer(), WebSocketPeer.WRITE_MODE_TEXT)

func connect_to_room_id(server_url: String, room_id: String, player_name: String) -> void:
	print("[NetworkManager] Joining specific room: %s" % room_id)
	_server_url = server_url
	local_player_name = player_name
	_state = ConnectionState.CONNECTING
	# 用 joinById endpoint
	var http_base = server_url.replace("ws://","http://").replace("wss://","https://")
	var url = "%s/matchmake/joinById/%s" % [http_base, room_id]
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(res, code, _h, body):
		_on_matchmake_done(res, code, body, http))
	http.request(url, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify({"playerName": player_name}))

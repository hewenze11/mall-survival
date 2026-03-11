extends Node

# ─── 信号 ─────────────────────────────────────────────────────
signal connected
signal disconnected
signal state_updated(state: Dictionary)
signal player_joined(id: String, data: Dictionary)
signal player_left(id: String)
signal phase_changed(phase: String, countdown: float)
signal damage_received(amount: int)

# ─── 状态 ─────────────────────────────────────────────────────
enum State { IDLE, CONNECTING, CONNECTED, DISCONNECTED }

var local_player_name: String = "Player"
var local_player_id: String = ""
var game_state: Dictionary = {}
var current_state: State = State.IDLE

var _ws: WebSocketPeer = null
var _server_http: String = ""
var _ping_timer: float = 0.0

const SERVER_HTTP = "http://104.64.211.23:2567"
const SERVER_WS   = "ws://104.64.211.23:2567"

# ─── 连接流程 ──────────────────────────────────────────────────
func join_game(player_name: String) -> void:
	local_player_name = player_name
	current_state = State.CONNECTING
	_server_http = SERVER_HTTP
	_do_matchmake("/matchmake/joinOrCreate/game", {"playerName": player_name})

func join_room(room_id: String, player_name: String) -> void:
	local_player_name = player_name
	current_state = State.CONNECTING
	_server_http = SERVER_HTTP
	_do_matchmake("/matchmake/joinById/" + room_id, {"playerName": player_name})

func _do_matchmake(endpoint: String, body: Dictionary) -> void:
	print("[NM] POST %s%s" % [_server_http, endpoint])
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(res, code, _h, raw_body):
		_on_matchmake_response(res, code, raw_body, http))
	http.request(
		_server_http + endpoint,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)

func _on_matchmake_response(result: int, code: int, raw_body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[NM] Matchmake failed: result=%d code=%d" % [result, code])
		current_state = State.DISCONNECTED
		disconnected.emit()
		return

	var j = JSON.new()
	if j.parse(raw_body.get_string_from_utf8()) != OK:
		print("[NM] JSON parse failed")
		disconnected.emit()
		return

	var data = j.get_data()
	var room = data.get("room", {})
	var room_id = room.get("roomId", "")
	var session_id = data.get("sessionId", "")
	local_player_id = session_id

	print("[NM] Got roomId=%s sessionId=%s" % [room_id, session_id])
	_connect_ws(room_id, session_id)

func _connect_ws(room_id: String, session_id: String) -> void:
	var url = "%s/%s?sessionId=%s" % [SERVER_WS, room_id, session_id]
	print("[NM] WS connect: %s" % url)
	_ws = WebSocketPeer.new()
	_ws.connect_to_url(url)

# ─── _process ─────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var ws_state = _ws.get_ready_state()

	if ws_state == WebSocketPeer.STATE_OPEN:
		if current_state != State.CONNECTED:
			current_state = State.CONNECTED
			print("[NM] WebSocket connected!")
			connected.emit()

		# 读取所有消息
		while _ws.get_available_packet_count() > 0:
			var pkt = _ws.get_packet()
			_handle_packet(pkt.get_string_from_utf8())

		# Ping
		_ping_timer += delta
		if _ping_timer >= 5.0:
			_ping_timer = 0.0
			_send({"type": "ping"})

	elif ws_state == WebSocketPeer.STATE_CLOSED:
		if current_state == State.CONNECTED:
			print("[NM] WebSocket closed")
			current_state = State.DISCONNECTED
			disconnected.emit()
		_ws = null

func _handle_packet(text: String) -> void:
	var j = JSON.new()
	if j.parse(text) != OK:
		return
	var msg = j.get_data()
	if typeof(msg) != TYPE_DICTIONARY:
		return
	var t = msg.get("type", "")

	match t:
		"state":
			game_state = msg.get("state", {})
			state_updated.emit(game_state)
		"playerJoined":
			player_joined.emit(msg.get("id",""), msg.get("data",{}))
		"playerLeft":
			player_left.emit(msg.get("id",""))
		"phaseChange":
			phase_changed.emit(msg.get("phase",""), msg.get("countdown", 0.0))
		"damage":
			damage_received.emit(msg.get("amount", 0))
		"pong":
			pass

# ─── 发送 ─────────────────────────────────────────────────────
func _send(data: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(data))

func send_move(x: float, y: float, dir: String) -> void:
	_send({"type":"move", "x":x, "y":y, "dir":dir})

func send_shoot(tx: float, ty: float) -> void:
	_send({"type":"shoot", "targetX":tx, "targetY":ty})

func send_pickup(item_id: String) -> void:
	_send({"type":"pickup", "itemId":item_id})

func send_use_item(item_key: String) -> void:
	_send({"type":"useItem", "itemKey":item_key})

func is_connected_to_room() -> bool:
	return current_state == State.CONNECTED

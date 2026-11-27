class_name NetProtocol
extends RefCounted
## Message shapes and the server-side checks on client input. Pure static functions, unit tested
## (game/tests/test_net_protocol.gd). Messages are Dictionaries with a "t" string key, sent with var_to_bytes.

const MSG_HELLO: String = "hello"
const MSG_WELCOME: String = "welcome"
const MSG_REJECT: String = "reject"
const MSG_LOBBY: String = "lobby"
const MSG_READY: String = "ready"
const MSG_START: String = "start"
const MSG_STATE: String = "state"
const MSG_SNAP: String = "snap"
const MSG_PEER_LEFT: String = "peer_left"
const MSG_RESULTS: String = "results"
const MSG_BYE: String = "bye"
const MSG_PING: String = "ping"
const MSG_PONG: String = "pong"


## "" when the hello is accepted, else the reason sent back to the client.
static func check_hello(version: int, player_name: String) -> String:
	if version != NetConfig.PROTOCOL_VERSION:
		return "version mismatch: server %d, client %d" % [NetConfig.PROTOCOL_VERSION, version]
	var clean: String = player_name.strip_edges()
	if clean.is_empty() or clean.length() > NetConfig.MAX_NAME_LEN:
		return "name must be 1 to %d characters" % NetConfig.MAX_NAME_LEN
	return ""


static func vec_finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


static func xf_finite(xf: Transform3D) -> bool:
	return vec_finite(xf.origin) and vec_finite(xf.basis.x) and vec_finite(xf.basis.y) and vec_finite(xf.basis.z)


## Car state as sent by a client: sequence number, world transform, velocity (m/s), steer (-1..1).
static func make_state(seq: int, xf: Transform3D, vel: Vector3, steer: float) -> Dictionary:
	return {"seq": seq, "xf": xf, "vel": vel, "steer": steer}


## "" when the new state may follow prev (the last accepted state of this car, empty for the first one).
## dt is the server-side time since prev was accepted. Rejects malformed, non-finite, too fast,
## out-of-order and teleporting states.
static func validate_state(prev: Dictionary, st: Dictionary, dt: float) -> String:
	if not (st.get("seq") is int and st.get("xf") is Transform3D and st.get("vel") is Vector3 and st.get("steer") is float):
		return "malformed state"
	var xf: Transform3D = st["xf"]
	var vel: Vector3 = st["vel"]
	var steer: float = st["steer"]
	if not (xf_finite(xf) and vec_finite(vel) and is_finite(steer)):
		return "non-finite state"
	if absf(steer) > 1.01:
		return "steer out of range"
	var speed: float = vel.length()
	if speed > NetConfig.MAX_SPEED_MS:
		return "speed %.1f m/s over the limit" % speed
	if prev.is_empty():
		return ""
	var prev_seq: int = prev["seq"]
	if int(st["seq"]) <= prev_seq:
		return "sequence not increasing"
	var prev_speed: float = (prev["vel"] as Vector3).length()
	var prev_xf: Transform3D = prev["xf"]
	var allowed: float = maxf(speed, prev_speed) * maxf(dt, 0.05) * NetConfig.JUMP_FACTOR + NetConfig.JUMP_SLACK_M
	var jump: float = prev_xf.origin.distance_to(xf.origin)
	if jump > allowed:
		return "teleport %.1f m in %.3f s (limit %.1f m)" % [jump, dt, allowed]
	return ""

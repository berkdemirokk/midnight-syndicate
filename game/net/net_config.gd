class_name NetConfig
extends RefCounted
## LAN / local multiplayer settings (experimental). Online is OFF by default: the menu button and the
## network code only run when ENABLED is true or the command line has --experimental-online.
## The server binds 127.0.0.1 unless a LAN address is passed explicitly. Not internet multiplayer.

const ENABLED: bool = false
const FLAG: String = "--experimental-online"
const PROTOCOL_VERSION: int = 1
const DEFAULT_PORT: int = 24580
const DEFAULT_BIND: String = "127.0.0.1"
const MAX_PLAYERS: int = 8  ## the grid has 8 slots
const MIN_START_READY: int = 2  ## the countdown starts when this many players are ready
const SNAP_HZ: float = 20.0  ## client car state rate
const INTERP_DELAY_S: float = 0.1  ## remote cars are drawn this far behind the newest snapshot
const COUNTDOWN_S: float = 3.0
const FINISH_WAIT_S: float = 15.0  ## after the first finish, unfinished cars get this long, then DNF
const MAX_SPEED_MS: float = 120.0  ## server rejects faster states
const JUMP_FACTOR: float = 1.5  ## allowed position jump = max speed * dt * JUMP_FACTOR + JUMP_SLACK_M
const JUMP_SLACK_M: float = 2.0
const RESET_TRIGGER_M: float = 12.0  ## client: a move this long between two sent states counts as a reset
const MAX_STATES_PER_S: int = 40  ## server: states accepted per car per second (2 x SNAP_HZ), the rest are dropped
const MAX_PROGRESS_JUMPS: int = 200  ## server: bad track projections per car before it is DNF (about 3 s at 60 fps)
const MAX_NAME_LEN: int = 24
const MAX_PACKET_BYTES: int = 65536
const SERVER_CHANNEL: int = 0
const TRACK_SCENE: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"  ## the race track, chosen by the server
const TRACK_ALLOW: PackedStringArray = [TRACK_SCENE]  ## the only track scenes a start message may name
const ORDER_HZ: float = 4.0  ## server: live standings (place, lap, metres) for every racer


## The track scene a start message names when it is allow-listed, else "" (the development circuit).
static func track_for(path: String) -> String:
	return path if TRACK_ALLOW.has(path) else ""


## True when the server may bind this address: loopback always, anything else only when given with --address.
static func bind_allowed(address: String) -> bool:
	if address == DEFAULT_BIND:
		return true
	return address != "" and address == cmdline_value("address", "")


## True when the online menu entry and the network code may run.
static func is_enabled() -> bool:
	return ENABLED or OS.get_cmdline_user_args().has(FLAG) or OS.get_cmdline_args().has(FLAG)


## Reads --key=value from the user command line (after --), else default.
static func cmdline_value(key: String, default: String) -> String:
	var prefix: String = "--%s=" % key
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return default

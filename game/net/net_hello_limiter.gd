class_name NetHelloLimiter
extends RefCounted
## Caps hello attempts per remote address (NetConfig.HELLO_MAX per HELLO_WINDOW_S), so a join code cannot be
## guessed by brute force from one address. The clock is passed in, so the rule is unit tested without sockets.
## Refused attempts are not recorded: the address gets back in once its earliest attempt leaves the window.

var _times: Dictionary = {}  ## remote address (String) -> attempt times in seconds, inside the window


## True when this attempt is allowed (and recorded), false when the address has used up its attempts.
func allow(address: String, now_s: float) -> bool:
	var kept: Array = []
	for t: Variant in _times.get(address, []):
		if now_s - float(t) < NetConfig.HELLO_WINDOW_S:
			kept.append(t)
	if kept.size() >= NetConfig.HELLO_MAX:
		_times[address] = kept
		return false
	kept.append(now_s)
	_times[address] = kept
	return true

extends "res://tests/test_case.gd"
## LAN join code and the hello rate limit (game/net/net_protocol.gd, net_hello_limiter.gd). Pure logic, no sockets.
## The server-side refusal of a wrong code over ENet is covered by tools/net_smoke.py (wrong_code_refused).


func test_join_code_format() -> void:
	var seen: Dictionary = {}
	for i: int in 50:
		var code: String = NetProtocol.make_code()
		check(code.length() == NetConfig.CODE_LEN, "generated code '%s' has %d characters" % [code, NetConfig.CODE_LEN])
		check(NetProtocol.code_valid(code), "generated code '%s' uses only the join code alphabet" % code)
		for bad: String in ["0", "O", "1", "I", "L"]:
			check(code.find(bad) < 0, "generated code '%s' has no look-alike '%s'" % [code, bad])
		seen[code] = true
	check(seen.size() > 40, "50 random codes are mostly different, got %d" % seen.size())
	check(not NetProtocol.code_valid("ABCDE"), "a 5-character code is refused")
	check(not NetProtocol.code_valid("ABCDEF7"), "a 7-character code is refused")
	check(not NetProtocol.code_valid("ABCDE0"), "a code with 0 is refused")
	check(NetProtocol.code_valid(NetProtocol.normalize_code("  abcdef  ")), "a typed code is trimmed and upper-cased")


func test_right_and_wrong_code() -> void:
	var code: String = "K7QF2M"
	check(NetProtocol.code_matches(code, "K7QF2M"), "the right code is accepted")
	check(NetProtocol.code_matches(code, " k7qf2m "), "the right code in lower case with spaces is accepted")
	check(not NetProtocol.code_matches(code, "K7QF2N"), "one wrong character is refused")
	check(not NetProtocol.code_matches(code, ""), "an empty code is refused")
	check(not NetProtocol.code_matches(code, "K7QF2"), "a short code is refused")
	check(not NetProtocol.code_matches(code, 123456), "a non-text code is refused")
	check(not NetProtocol.code_matches("", ""), "a host without a valid code matches nothing")


func test_hello_rate_limit() -> void:
	var lim := NetHelloLimiter.new()
	var allowed: int = 0
	for i: int in NetConfig.HELLO_MAX + 3:
		if lim.allow("192.168.1.9", 100.0 + 0.1 * i):
			allowed += 1
	check(allowed == NetConfig.HELLO_MAX, "%d hello attempts in one window are allowed, got %d" % [NetConfig.HELLO_MAX, allowed])
	check(lim.allow("10.0.0.2", 100.0), "another address is not limited by the first")
	check(lim.allow("192.168.1.9", 100.0 + NetConfig.HELLO_WINDOW_S + 0.5), "the address is allowed again after the window")
	var again: int = 0
	for i: int in NetConfig.HELLO_MAX + 2:
		if lim.allow("192.168.1.9", 200.0 + 0.1 * i):
			again += 1
	check(again == NetConfig.HELLO_MAX, "after the window the address gets its full allowance back, got %d" % again)

extends "res://tests/test_case.gd"
## Client reject and lost link (game/net/net_session.gd), and the server's hello deadline. The client handlers are
## driven directly, so no sockets are needed: the server's reject and the disconnect that follows it.


func test_rejected_connect_frees_the_client_role() -> void:
	var s := NetSession.new()
	var lost: Array = []
	s.connection_lost.connect(func(reason: String) -> void: lost.append(reason))
	check(s.connect_to_server("127.0.0.1", NetConfig.DEFAULT_PORT + 9, "Tester", "K7QF2M") == "", "first connect starts")
	s._client_message(NetProtocol.MSG_REJECT, {"reason": "wrong join code", "key": NetProtocol.REJECT_CODE})
	s._on_disconnect(null)
	check(s.role == NetSession.ROLE_NONE, "a rejected client leaves role NONE, got %d" % s.role)
	check(s.last_message == "wrong join code", "the reject text is kept, got '%s'" % s.last_message)
	check(s.last_reject_key == NetProtocol.REJECT_CODE, "the reject key is kept")
	check(lost.is_empty(), "a reject is not reported as a lost connection")
	check(s.connect_to_server("127.0.0.1", NetConfig.DEFAULT_PORT + 9, "Tester", "K7QF2M") == "", "a second connect is allowed after a reject")
	check(s.last_reject_key == "", "the reject key is cleared by the new connect")
	s.close()
	s.free()


func test_lost_link_is_still_reported() -> void:
	var s := NetSession.new()
	var lost: Array = []
	s.connection_lost.connect(func(reason: String) -> void: lost.append(reason))
	s.connect_to_server("127.0.0.1", NetConfig.DEFAULT_PORT + 9, "Tester", "K7QF2M")
	s._on_disconnect(null)
	check(lost.size() == 1, "a dropped link emits connection_lost once, got %d" % lost.size())
	check(s.last_message == NetSession.LOST_MESSAGE, "the lost message is set")
	check(s.role == NetSession.ROLE_NONE, "a dropped client leaves role NONE")
	s.free()


func test_hello_deadline() -> void:
	check(not NetSession.hello_overdue(10.0, 10.0 + NetConfig.HELLO_DEADLINE_S), "a hello exactly at the deadline is in time")
	check(NetSession.hello_overdue(10.0, 10.0 + NetConfig.HELLO_DEADLINE_S + 0.1), "a hello past the deadline is overdue")
	check(not NetSession.hello_overdue(10.0, 11.0), "a fresh connection is not overdue")
	check(NetConfig.HELLO_DEADLINE_S == 5.0, "the hello deadline is 5 s")

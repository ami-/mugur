package main
import "core:testing"

@(test)
test_decode_ascii :: proc(t: ^testing.T) {
	ev, used := decode_one(transmute([]u8)string("a"))
	testing.expect_value(t, used, 1)
	testing.expect_value(t, ev, Event(Key_Event{key = .Char, r = 'a'}))
}

@(test)
test_decode_arrows :: proc(t: ^testing.T) {
	Case :: struct {
		input: string,
		key:   Key,
	}
	cases := []Case{{"\x1b[A", .Up}, {"\x1b[B", .Down}, {"\x1b[C", .Right}, {"\x1b[D", .Left}}

	for c in cases {
		ev, used := decode_one(transmute([]u8)c.input)
		testing.expect_value(t, used, 3)
		testing.expect_value(t, ev, Event(Key_Event{key = c.key}))
	}
}

@(test)
test_decode_incomplete :: proc(t: ^testing.T) {
	inputs := []string{"\x1b", "\x1b["}
	for input in inputs {
		_, used := decode_one(transmute([]u8)input)
		testing.expect_value(t, used, 0)
	}
}

@(test)
test_decode_leaves_rest :: proc(t: ^testing.T) {
	ev, used := decode_one(transmute([]u8)string("\x1b[Cx"))
	testing.expect_value(t, used, 3)
	testing.expect_value(t, ev, Event(Key_Event{key = .Right}))
}

@(test)
test_decode_all :: proc(t: ^testing.T) {
	events: [dynamic]Event
	defer delete(events)

	input := "a\x1b[Cb\x1b["
	used := decode_all(transmute([]u8)input, &events)

	testing.expect_value(t, used, 5) // "a", "\x1b[C", "b" -- "\x1b[" is left over
	if !testing.expect_value(t, len(events), 3) {
		return // don't index into events if the count is wrong
	}

	testing.expect_value(t, events[0], Event(Key_Event{key = .Char, r = 'a'}))
	testing.expect_value(t, events[1], Event(Key_Event{key = .Right}))
	testing.expect_value(t, events[2], Event(Key_Event{key = .Char, r = 'b'}))
}

@(test)
test_decode_all_skips_unknown :: proc(t: ^testing.T) {
	events: [dynamic]Event
	defer delete(events)

	used := decode_all(transmute([]u8)string("\xffa"), &events)
	testing.expect_value(t, used, 2)
	testing.expect_value(t, len(events), 1)
}

@(test)
test_decode_control_keys :: proc(t: ^testing.T) {
	Case :: struct {
		input: string,
		want:  Key_Event,
	}
	cases := []Case {
		{"\r", {key = .Enter}},
		{"\n", {key = .Enter}},
		{"\x7f", {key = .Backspace}},
		{"\x11", {key = .Char, r = 'q', mods = {.Ctrl}}},
		{"\x01", {key = .Char, r = 'a', mods = {.Ctrl}}},
	}
	for c in cases {
		ev, size := decode_one(transmute([]u8)c.input)
		testing.expect_value(t, size, 1)
		testing.expect_value(t, ev, Event(c.want))
	}
}

@(test)
test_decode_utf8 :: proc(t: ^testing.T) {
	ev, size := decode_one(transmute([]u8)string("é"))
	testing.expect_value(t, size, 2)
	testing.expect_value(t, ev, Event(Key_Event{key = .Char, r = 'é'}))

	ev, size = decode_one(transmute([]u8)string("🙂x"))
	testing.expect_value(t, size, 4)
	testing.expect_value(t, ev, Event(Key_Event{key = .Char, r = '🙂'}))
}

@(test)
test_decode_utf8_incomplete_and_invalid :: proc(t: ^testing.T) {
	_, size := decode_one([]u8{0xc3}) // first byte of "é"
	testing.expect_value(t, size, 0)

	ev: Event
	ev, size = decode_one([]u8{0xff}) // never valid in UTF-8
	testing.expect_value(t, size, 1)
	testing.expect_value(t, ev, nil)
}

@(test)
test_decode_timeout :: proc(t: ^testing.T) {
	events: [dynamic]Event
	defer delete(events)

	decode_timeout([]u8{ESC}, &events)
	decode_timeout(transmute([]u8)string("\x1b["), &events) // dropped
	if !testing.expect_value(t, len(events), 1) {
		return
	}
	testing.expect_value(t, events[0], Event(Key_Event{key = .Escape}))
}

package main
import "core:unicode/utf8"

ESC :: 0x1b

Key :: enum {
	Char, // printable character; the rune is in Key_Event.r
	Enter,
	Backspace,
	Escape,
	Up,
	Down,
	Left,
	Right,
}

Modifier :: enum {
	Shift,
	Alt,
	Ctrl,
}

Modifiers :: bit_set[Modifier]

Key_Event :: struct {
	key:  Key,
	r:    rune,
	mods: Modifiers,
}

Event :: union {
	Key_Event,
}
//decodes from start of `bytes`.
//returns an Event and how many bytes it used.
//size == 0 means: not enough bytes yet (wait for more input).
decode_one :: proc(bytes: []u8) -> (ev: Event, used: int) {
	if len(bytes) == 0 {
		return nil, 0
	}
	b := bytes[0]

	if b == ESC {
		return decode_escape(bytes)
	}

	switch b {
	case '\r', '\n':
		return Key_Event{key = .Enter}, 1
	case 127, 8:
		//most terminals send 127(DEL), some 8 (CTRL+H)
		return Key_Event{key = .Backspace}, 1
	case 1 ..= 26:
		//CTRL+A .. CTRL+Z
		//Ctrl+Q is 0x11 = 17, so 17 − 1 = 16, and 'a' + 16 = 'q'
		return Key_Event{key = .Char, r = 'a' + rune(b - 1), mods = {.Ctrl}}, 1
	}

	if b >= 0x80 {
		return decode_utf8(bytes)
	}

	if b >= 32 && b < 127 {
		//printable char
		return Key_Event{key = .Char, r = rune(b)}, 1
	}
	//unknown byte, skip it
	return nil, 1
}

// decodes as many events as possible from `bytes` and appends them to `events`
// returns how many bytes were used
decode_all :: proc(bytes: []u8, events: ^[dynamic]Event) -> (used: int) {
	for used < len(bytes) {
		ev, so_far := decode_one(bytes[used:])
		if so_far == 0 {
			break //incomplete sequence: wait for more input
		}
		if ev != nil {
			//got one
			append(events, ev)
		}
		used += so_far
	}
	return
}

// ESC [ A/B/C/D
decode_escape :: proc(bytes: []u8) -> (ev: Event, used: int) {
	if len(bytes) < 2 {
		return nil, 0 // single ESC, more should come
	}

	if bytes[1] != '[' {
		return nil, 1 //not an ESC sequence: skip it
	}

	if len(bytes) < 3 {
		return nil, 0 // got the start `ESC [`  wait for more
	}

	key: Key
	switch bytes[2] {
	case 'A':
		key = .Up
	case 'B':
		key = .Down
	case 'C':
		key = .Right
	case 'D':
		key = .Left
	case:
		return nil, 3 // unknown sequence: skipt it
	}
	return Key_Event{key = key}, 3
}

// multi-byte utf-8 character
decode_utf8 :: proc(bytes: []u8) -> (ev: Event, used: int) {
	if !utf8.full_rune(bytes) {
		return nil, 0 // incomplete: wait for more
	}
	r, n := utf8.decode_rune(bytes)
	if r == utf8.RUNE_ERROR && n == 1 {
		return nil, 1 // invalid byte: skip it
	}
	return Key_Event{key = .Char, r = r}, n
}

//called when no new bytes arrived for a while so not a sequence
// a lone ESC was Escape key
decode_timeout :: proc(bytes: []u8, events: ^[dynamic]Event) {
	if len(bytes) == 1 && bytes[0] == ESC {
		append(events, Key_Event{key = .Escape})
	}
}

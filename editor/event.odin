package editor

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

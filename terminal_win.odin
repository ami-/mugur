#+build windows
package main

import win32 "core:sys/windows"

@(private = "file")
orig_mode: win32.DWORD

enable_raw_mode :: proc() {
	stdin := win32.GetStdHandle(win32.STD_INPUT_HANDLE)
	assert(stdin != win32.INVALID_HANDLE_VALUE)

	// Save original console mode
	ok := win32.GetConsoleMode(stdin, &orig_mode)
	assert(ok)

	raw := orig_mode
	// Disable line input and echo input
	raw &= ~win32.ENABLE_ECHO_INPUT
	raw &= ~win32.ENABLE_LINE_INPUT

	ok = win32.SetConsoleMode(stdin, raw)
	assert(ok)
}

disable_raw_mode :: proc "c" () {
	stdin := win32.GetStdHandle(win32.STD_INPUT_HANDLE)
	if stdin != win32.INVALID_HANDLE_VALUE {
		win32.SetConsoleMode(stdin, orig_mode)
	}
}

get_terminal_size :: proc() -> (rows, cols: int, ok: bool) {
	h := win32.GetStdHandle(win32.STD_OUTPUT_HANDLE)
	if h == win32.INVALID_HANDLE_VALUE {
		return 0, 0, false
	}

	csbi: win32.CONSOLE_SCREEN_BUFFER_INFO
	if !win32.GetConsoleScreenBufferInfo(h, &csbi) {
		return 0, 0, false
	}

	width := int(csbi.srWindow.Right - csbi.srWindow.Left + 1)
	height := int(csbi.srWindow.Bottom - csbi.srWindow.Top + 1)
	return height, width, true
}

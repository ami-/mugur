#+build windows
package tui

import win32 "core:sys/windows"

@(private = "file")
orig_in_mode: win32.DWORD

@(private = "file")
orig_out_mode: win32.DWORD

// Windows has no SIGTSTP/SIGCONT (Ctrl+Z, fg), so this is never set
resumed: bool

enable_raw_mode :: proc() {
	stdin := win32.GetStdHandle(win32.STD_INPUT_HANDLE)
	assert(stdin != win32.INVALID_HANDLE_VALUE)
	stdout := win32.GetStdHandle(win32.STD_OUTPUT_HANDLE)
	assert(stdout != win32.INVALID_HANDLE_VALUE)

	// Save original console modes
	ok := win32.GetConsoleMode(stdin, &orig_in_mode)
	assert(bool(ok))
	ok = win32.GetConsoleMode(stdout, &orig_out_mode)
	assert(bool(ok))

	raw_in := orig_in_mode
	// Disable line input and echo input
	raw_in &= ~win32.ENABLE_ECHO_INPUT
	raw_in &= ~win32.ENABLE_LINE_INPUT
	// Deliver keys as escape sequences (arrows as ESC [ A ...), like a unix terminal
	raw_in |= win32.ENABLE_VIRTUAL_TERMINAL_INPUT

	ok = win32.SetConsoleMode(stdin, raw_in)
	assert(bool(ok))

	// Interpret the ANSI escape sequences we write (cursor moves, colors, alternate screen)
	ok = win32.SetConsoleMode(stdout, orig_out_mode | win32.ENABLE_VIRTUAL_TERMINAL_PROCESSING)
	assert(bool(ok))
}

disable_raw_mode :: proc "c" () {
	stdin := win32.GetStdHandle(win32.STD_INPUT_HANDLE)
	if stdin != win32.INVALID_HANDLE_VALUE {
		win32.SetConsoleMode(stdin, orig_in_mode)
	}
	stdout := win32.GetStdHandle(win32.STD_OUTPUT_HANDLE)
	if stdout != win32.INVALID_HANDLE_VALUE {
		win32.SetConsoleMode(stdout, orig_out_mode)
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

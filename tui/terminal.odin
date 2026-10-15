package tui

import "../editor"
import "core:c/libc"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:sync"
import "core:terminal/ansi"

@(private)
STATUS_LINE :: 1

@(private)
Terminal :: struct {
	// size of screen
	dims:          [2]int,

	// screen buffer
	screen_buffer: strings.Builder,
}

make_terminal :: proc() -> Terminal {
	t := Terminal{}
	r, c, ok := get_terminal_size()
	if !ok {
		panic("could not get terminal size")
	}
	t.dims = {r, c}
	t.screen_buffer = strings.builder_make_len_cap(0, t.dims.x * t.dims.y)

	//reserve status
	t.dims.x -= STATUS_LINE

	return t
}

destroy_terminal :: proc(t: ^Terminal) {
	strings.builder_destroy(&t.screen_buffer)
}

@(private)
check_resize :: proc(t: ^Terminal) -> bool {
	rows, cols, ok := get_terminal_size()
	if !ok {
		return false
	}
	new_dims := [2]int{rows - STATUS_LINE, cols}

	if new_dims == t.dims {
		//nothing changed
		return false
	}
	t.dims = new_dims

	return true
}


run :: proc(ed: ^editor.Editor) {
	enable_raw_mode()
	libc.atexit(disable_raw_mode)

	//alternate buffer screen
	fmt.print(ansi.CSI + ansi.DECASB_ENTER)

	t := make_terminal()
	defer destroy_terminal(&t)

	view(&t, ed)

	buf: [64]byte
	pending := 0 //bytes at start of buf left over from prev read
	events: [dynamic]editor.Event
	defer delete(events)

	main_loop: for {
		n_read, err := os.read(os.stdin, buf[pending:])
		if err != nil && err != io.Error.EOF {
			fmt.eprintf("err: %v", err)
			break
		}
		have := pending + n_read

		clear(&events)
		used := decode_all(buf[:have], &events)
		pending = copy(buf[:], buf[used:have]) //move leftover bytes to front

		if n_read == 0 && pending > 0 {
			// VTIME != 0 means os.read does not block but returns after the configured
			// time spent (aprox). so ESC can be caught here by timing lack of sequence
			// based on VTIME ; 1 ~*10ms = 100ms have passed since last read
			decode_timeout(buf[:pending], &events)
			pending = 0
		}

		resized := check_resize(&t)
		was_resumed := sync.atomic_exchange(&resumed, false)

		for ev in events {
			if ev == editor.Event(editor.Key_Event{key = .Char, r = 'q', mods = {.Ctrl}}) {
				break main_loop
			}

			editor.update(ed, ev)
		}

		if len(events) > 0 || resized || was_resumed {
			view(&t, ed)
		}
	}

	//revert alternate buffer screen
	fmt.print(ansi.CSI + ansi.DECASB_EXIT)
}

package main

import "core:c/libc"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:sync"
import "core:terminal/ansi"


FILE :: "abc\nline"
STATUS_LINE :: 1

Terminal :: struct {
	//size of screen
	dims:          [2]int,
	//cursor position
	render_cursor: [2]int,

	//first line in buffer
	line_offset:   int,
	buf:           Gap_Buffer,
	screen_buffer: strings.Builder,
	status_left:   string,
	status_right:  string,
}

make_terminal :: proc(n_bytes: int = 4) -> Terminal {
	t := Terminal{}
	r, c, ok := get_terminal_size()
	if !ok {
		panic("could not get terminal size")
	}
	t.dims = {r, c}
	t.buf = make_gap_buffer(c)
	t.screen_buffer = strings.builder_make_len_cap(0, t.dims.x * t.dims.y)
	t.status_left = "Press CTRL+'q' to exit."
	t.status_right = "#"

	//reserve status
	t.dims.x -= STATUS_LINE

	t.render_cursor = {1, 1}
	return t
}
destroy_terminal :: proc(t: ^Terminal) {
	destroy_gap_buffer(&t.buf)
	strings.builder_destroy(&t.screen_buffer)
}

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


main :: proc() {
	enable_raw_mode()
	libc.atexit(disable_raw_mode)

	//alternate buffer screen
	fmt.print(ansi.CSI + ansi.DECASB_ENTER)

	t := make_terminal()
	view(&t)

	buf: [64]byte
	pending := 0 //bytes at start of buf left over from prev read
	events: [dynamic]Event
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
			if ev == Event(Key_Event{key = .Char, r = 'q', mods = {.Ctrl}}) {
				break main_loop
			}

			update(&t, ev)
		}

		if len(events) > 0 || resized || was_resumed {
			view(&t)
		}
	}

	//revert alternate buffer screen
	fmt.print(ansi.CSI + ansi.DECASB_EXIT)

	l, r := as_string_parts(&t.buf)
	fmt.println(l, r, sep = "")
}
update :: proc(t: ^Terminal, ev: Event) {
	gb := &t.buf
	switch e in ev {
	case Key_Event:
		switch e.key {
		case .Up:
			cursor_up(gb)
		case .Down:
			cursor_down(gb)
		case .Left:
			cursor_left(gb)
		case .Right:
			cursor_right(gb)
		case .Enter:
			insert(gb, gb.start, u8('\n'))
		case .Backspace:
			backspace(gb)
		case .Escape:
			t.status_left = "Escape pressed"
		case .Char:
			if e.mods == {} {
				insert(gb, gb.start, e.r)
			}}
	}
}

view :: proc(t: ^Terminal) {
	//erase_in_display(ERASE_ALL)
	b := &t.screen_buffer
	strings.builder_reset(b)

	// clear screen, cursor to top-left
	clear_screen(b)
	move_to(b, 1, 1)

	l, r := as_string_parts(&t.buf)
	fmt.sbprint(b, l, r, sep = "") // draw the whole text

	// cursor location
	row := strings.count(l, "\n")
	col := strings.rune_count(l[strings.last_index_byte(l, '\n') + 1:])

	draw_status(t, row, col)

	//show cursor in new location
	move_to(b, row + 1, col + 1) // terminal rows/cols start at 1

	fmt.print(strings.to_string(b^))
}


draw_status :: proc(t: ^Terminal, cursor_row, cursor_col: int) {
	b := &t.screen_buffer // only appends, no reset
	row := t.dims.x + 1
	cols := t.dims.y

	right_buf: [32]u8
	right := fmt.bprintf(right_buf[:], "[%d,%d]", cursor_row + 1, cursor_col + 1)
	gap := max(cols - strings.rune_count(t.status_left) - strings.rune_count(right), 0)

	move_to(b, row, 1)
	invert_colors(b)
	strings.write_string(b, t.status_left)
	for _ in 0 ..< gap {
		strings.write_byte(b, ' ')
	}
	strings.write_string(b, right)
	reset_style(b)
}

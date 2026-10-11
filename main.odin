package main

import "core:c/libc"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:sync"
import "core:terminal/ansi"


STATUS_LINE :: 1

Terminal :: struct {
	//size of screen
	dims:          [2]int,
	//cursor position
	render_cursor: [2]int,

	//scroll position
	line_offset:   int,
	col_offset:    int,
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
	load_text(&t.buf, FILE)

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

	_ = write_to(&t.buf, os.to_writer(os.stdout))
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
	b := &t.screen_buffer
	strings.builder_reset(b)

	text := as_text(&t.buf)
	defer free_all(context.temp_allocator)

	// cursor location
	row, col := cursor_line_col(&t.buf)

	scroll(t, row, col)

	rows := t.dims.x
	cols := t.dims.y
	i := 0
	for line in strings.split_lines_iterator(&text) {
		defer i += 1
		if i < t.line_offset {
			continue
		}
		if i >= t.line_offset + rows {
			break
		}
		move_to(b, i - t.line_offset + 1, 1)

		rc := 0
		lstart, lend := len(line), len(line)
		for _, idx in line {
			if rc == t.col_offset {
				lstart = idx
			}
			if rc == t.col_offset + cols {
				lend = idx
			}
			rc += 1
		}
		fmt.sbprint(b, line[lstart:lend]) // draw the line text

		fmt.sbprint(b, ansi.CSI + ansi.EL) //delete rest of line
	}
	//clear rest of screen
	for ; i < t.line_offset + rows; i += 1 {
		move_to(b, i - t.line_offset + 1, 1)
		fmt.sbprint(b, "~")
		fmt.sbprint(b, ansi.CSI + ansi.EL) //delete rest of line
	}


	draw_status(t, row, col)

	//show cursor in new location
	screen_row, screen_col := screen_pos(t, row, col)
	move_to(b, screen_row, screen_col)

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

scroll :: proc(t: ^Terminal, cursor_row, cursor_col: int) {
	rows := t.dims.x
	cols := t.dims.y
	if cursor_row < t.line_offset {
		t.line_offset = cursor_row
	}
	if cursor_row >= t.line_offset + rows {
		t.line_offset = cursor_row - rows + 1
	}
	if cursor_col < t.col_offset {
		t.col_offset = max(0, cursor_col - cols / 2)
	}
	if cursor_col >= t.col_offset + cols {
		t.col_offset = cursor_col - cols + 1
	}
}

// text position (0-based line and rune column) to terminal position (1-based),
// taking the scroll offsets into account
screen_pos :: proc(t: ^Terminal, row, col: int) -> (screen_row, screen_col: int) {
	return row - t.line_offset + 1, col - t.col_offset + 1
}


FILE :: `1. Line one
2. Line two
3. Line three
4. Line four
5. Line five
6. Line six
7. Line seven
8. Line eight
9. Line nine
10. Line ten
11. Line eleven
12. Line twelve
13. Line thirteen
14. Line fourteen
15. Line fifteen
16. Line sixteen
17. Line seventeen
18. Line eighteen
19. Line nineteen
20. Line twenty
21. Line twenty-one
22. Line twenty-two
23. Line twenty-three
24. Line twenty-four
25. Line twenty-five
26. Line twenty-six
27. Line twenty-seven
28. Line twenty-eight
29. Line twenty-nine
30. Line thirty
31. Line thirty-one
32. Line thirty-two
33. Line thirty-three
34. Line thirty-four
35. Line thirty-five
36. Line thirty-six
37. Line thirty-seven
38. Line thirty-eight
39. Line thirty-nine
40. Line forty
41. Line forty-one
42. Line forty-two
43. Line forty-three
44. Line forty-four
45. Line forty-five
46. Line forty-six
47. Line forty-seven
48. Line forty-eight
49. Line forty-nine
50. Line fifty`

package main

import "core:c/libc"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:sync"
import "core:terminal/ansi"
import "editor"


STATUS_LINE :: 1

QUIT_HINT :: "Press CTRL+'q' to exit"

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
	defer destroy_terminal(&t)

	ed := editor.make_editor()
	defer editor.destroy_editor(&ed)

	editor.load_text(&ed.buf, FILE)

	view(&t, &ed)

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

			editor.update(&ed, ev)
		}

		if len(events) > 0 || resized || was_resumed {
			view(&t, &ed)
		}
	}

	//revert alternate buffer screen
	fmt.print(ansi.CSI + ansi.DECASB_EXIT)

	_ = editor.write_to(&ed.buf, os.to_writer(os.stdout))
}

view :: proc(t: ^Terminal, ed: ^editor.Editor) {
	b := &t.screen_buffer
	strings.builder_reset(b)

	text := editor.as_text(&ed.buf)
	defer free_all(context.temp_allocator)

	// cursor location
	row, col := editor.cursor_line_col(&ed.buf)

	editor.scroll(ed, t.dims.x, t.dims.y, row, col)

	rows := t.dims.x
	cols := t.dims.y
	line_count := strings.count(text, "\n") + 1
	i := 0
	for line in strings.split_lines_iterator(&text) {
		defer i += 1
		if i < ed.line_offset {
			continue
		}
		if i >= ed.line_offset + rows {
			break
		}
		move_to(b, i - ed.line_offset + 1, 1)

		visible := editor.visible_part(line, ed.col_offset, cols)
		// draw the visible line text
		fmt.sbprint(b, visible)

		fmt.sbprint(b, ansi.CSI + ansi.EL) //delete rest of line
	}
	//clear rest of screen
	for ; i < ed.line_offset + rows; i += 1 {
		move_to(b, i - ed.line_offset + 1, 1)
		if i >= line_count {
			fmt.sbprint(b, "~")
		}
		fmt.sbprint(b, ansi.CSI + ansi.EL) //delete rest of line
	}


	draw_status(t, ed, row, col)

	//show cursor in new location
	screen_row, screen_col := screen_pos(ed, row, col)
	move_to(b, screen_row, screen_col)

	fmt.print(strings.to_string(b^))
}


draw_status :: proc(t: ^Terminal, ed: ^editor.Editor, cursor_row, cursor_col: int) {
	b := &t.screen_buffer // only appends, no reset
	row := t.dims.x + 1
	cols := t.dims.y

	msg := ed.status if ed.status != "" else QUIT_HINT

	right_buf: [32]u8
	right := fmt.bprintf(right_buf[:], "[%d,%d]", cursor_row + 1, cursor_col + 1)

	left := editor.visible_part(msg, 0, max(0, cols - strings.rune_count(right)))

	gap := max(cols - strings.rune_count(left) - strings.rune_count(right), 0)

	move_to(b, row, 1)

	invert_colors(b)
	strings.write_string(b, left)
	for _ in 0 ..< gap {
		strings.write_byte(b, ' ')
	}
	strings.write_string(b, right)
	reset_style(b)
}


// text position (0-based line and rune column) to terminal position (1-based),
// taking the scroll offsets into account
screen_pos :: proc(ed: ^editor.Editor, row, col: int) -> (screen_row, screen_col: int) {
	return row - ed.line_offset + 1, col - ed.col_offset + 1
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

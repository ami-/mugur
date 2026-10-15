package tui

import "../editor"
import "core:fmt"
import "core:strings"
import "core:terminal/ansi"

QUIT_HINT :: "Press CTRL+'q' to exit"

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

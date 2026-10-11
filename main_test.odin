package main
import "core:testing"

@(private = "file")
expect_offsets :: proc(
	t: ^testing.T,
	term: ^Terminal,
	want_line, want_col: int,
	loc := #caller_location,
) {
	testing.expect_value(t, term.line_offset, want_line, loc)
	testing.expect_value(t, term.col_offset, want_col, loc)
}

@(test)
test_scroll_vertical :: proc(t: ^testing.T) {
	term := Terminal {
		dims = {24, 80},
	}

	scroll(&term, 10, 0) // visible: nothing changes
	expect_offsets(t, &term, 0, 0)

	scroll(&term, 30, 0) // below the screen: cursor on the last row
	expect_offsets(t, &term, 7, 0)

	scroll(&term, 20, 0) // still visible
	expect_offsets(t, &term, 7, 0)

	scroll(&term, 3, 0) // above the screen: cursor on the first row
	expect_offsets(t, &term, 3, 0)
}

@(test)
test_scroll_horizontal :: proc(t: ^testing.T) {
	term := Terminal {
		dims = {24, 80},
	}

	scroll(&term, 0, 100) // end of a long line: cursor on the last column
	expect_offsets(t, &term, 0, 21)

	scroll(&term, 1, 10) // down onto a short line: back to the start
	expect_offsets(t, &term, 0, 0)

	scroll(&term, 0, 200) // far right
	expect_offsets(t, &term, 0, 121)

	scroll(&term, 1, 100) // left of the screen: cursor centered
	expect_offsets(t, &term, 0, 60)
}

@(test)
test_screen_pos :: proc(t: ^testing.T) {
	term := Terminal {
		dims = {24, 80},
	}

	r, c := screen_pos(&term, 0, 0) // terminal starts at 1,1
	testing.expect_value(t, r, 1)
	testing.expect_value(t, c, 1)

	term.line_offset, term.col_offset = 10, 28
	r, c = screen_pos(&term, 12, 58)
	testing.expect_value(t, r, 3)
	testing.expect_value(t, c, 31)
}

// after scroll, the cursor must always land inside the text area
@(test)
test_scroll_keeps_cursor_on_screen :: proc(t: ^testing.T) {
	term := Terminal {
		dims = {24, 80},
	}

	moves := [][2]int{{0, 100}, {1, 10}, {1, 58}, {50, 0}, {0, 0}, {40, 300}, {41, 2}, {23, 79}, {24, 80}}
	for m in moves {
		scroll(&term, m[0], m[1])
		r, c := screen_pos(&term, m[0], m[1])
		testing.expectf(t, 1 <= r && r <= term.dims.x, "row %d off screen after moving to %v", r, m)
		testing.expectf(t, 1 <= c && c <= term.dims.y, "col %d off screen after moving to %v", c, m)
	}
}

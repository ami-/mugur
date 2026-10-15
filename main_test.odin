package main
import "core:testing"
import "editor"

@(test)
test_screen_pos :: proc(t: ^testing.T) {
	ed := editor.Editor{}

	r, c := screen_pos(&ed, 0, 0) // terminal starts at 1,1
	testing.expect_value(t, r, 1)
	testing.expect_value(t, c, 1)

	ed.line_offset, ed.col_offset = 10, 28
	r, c = screen_pos(&ed, 12, 58)
	testing.expect_value(t, r, 3)
	testing.expect_value(t, c, 31)
}

// after scroll, the cursor must always land inside the text area
@(test)
test_scroll_keeps_cursor_on_screen :: proc(t: ^testing.T) {
	ed := editor.Editor{}

	moves := [][2]int {
		{0, 100},
		{1, 10},
		{1, 58},
		{50, 0},
		{0, 0},
		{40, 300},
		{41, 2},
		{23, 79},
		{24, 80},
	}
	for m in moves {
		editor.scroll(&ed, 24, 80, m[0], m[1])
		r, c := screen_pos(&ed, m[0], m[1])
		testing.expectf(t, 1 <= r && r <= 24, "row %d off screen after moving to %v", r, m)
		testing.expectf(t, 1 <= c && c <= 80, "col %d off screen after moving to %v", c, m)
	}
}

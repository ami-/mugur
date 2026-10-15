package editor

import "core:testing"

@(private = "file")
press :: proc(ed: ^Editor, key: Key, times := 1) {
	for _ in 0 ..< times {
		update(ed, Key_Event{key = key})
	}
}
@(private = "file")
expect_offsets :: proc(
	t: ^testing.T,
	ed: ^Editor,
	want_line, want_col: int,
	loc := #caller_location,
) {
	testing.expect_value(t, ed.line_offset, want_line, loc)
	testing.expect_value(t, ed.col_offset, want_col, loc)
}

@(test)
test_scroll_vertical :: proc(t: ^testing.T) {
	ed := Editor{}

	scroll(&ed, 24, 80, 10, 0) // visible: nothing changes
	expect_offsets(t, &ed, 0, 0)

	scroll(&ed, 24, 80, 30, 0) // below the screen: cursor on the last row
	expect_offsets(t, &ed, 7, 0)

	scroll(&ed, 24, 80, 20, 0) // still visible
	expect_offsets(t, &ed, 7, 0)

	scroll(&ed, 24, 80, 3, 0) // above the screen: cursor on the first row
	expect_offsets(t, &ed, 3, 0)
}

@(test)
test_scroll_horizontal :: proc(t: ^testing.T) {
	ed := Editor{}

	scroll(&ed, 24, 80, 0, 100) // end of a long line: cursor on the last column
	expect_offsets(t, &ed, 0, 21)

	scroll(&ed, 24, 80, 1, 10) // down onto a short line: back to the start
	expect_offsets(t, &ed, 0, 0)

	scroll(&ed, 24, 80, 0, 200) // far right
	expect_offsets(t, &ed, 0, 121)

	scroll(&ed, 24, 80, 1, 100) // left of the screen: cursor centered
	expect_offsets(t, &ed, 0, 60)
}

@(test)
test_visible_part :: proc(t: ^testing.T) {
	Case :: struct {
		line:          string,
		offset, width: int,
		want:          string,
	}
	cases := []Case {
		{"hello world", 0, 5, "hello"},
		{"", 0, 5, ""},
		// offset at the end
		{"abc", 3, 5, ""},
		{"世界abc", 0, 1, "世"},
		// short line
		{"hello world", 15, 5, ""},
		{"こんにちは世界", 5, 2, "世界"},
	}
	for c in cases {
		got := visible_part(c.line, c.offset, c.width)
		testing.expectf(
			t,
			got == c.want,
			"visible_part(%q, %d, %d) = %q, want %q",
			c.line,
			c.offset,
			c.width,
			got,
			c.want,
		)
	}
}

@(test)
test_update_remembers_column :: proc(t: ^testing.T) {
	TEXT :: "a long line of text\nab\nanother long line"
	ed := make_editor()
	defer destroy_editor(&ed)
	load_text(&ed.buf, TEXT)

	press(&ed, .Right, 10)
	expect_cursor(t, &ed.buf, 0, 10)

	press(&ed, .Down)
	expect_cursor(t, &ed.buf, 1, 2)

	press(&ed, .Escape)

	press(&ed, .Down)
	expect_cursor(t, &ed.buf, 2, 10)

	press(&ed, .Up, 2)
	expect_cursor(t, &ed.buf, 0, 10)

	press(&ed, .Left)
	expect_cursor(t, &ed.buf, 0, 9)

	press(&ed, .Down, 2)
	expect_cursor(t, &ed.buf, 2, 9)
}

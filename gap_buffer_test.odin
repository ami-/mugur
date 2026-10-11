package main
import "core:fmt"
import "core:strings"
import "core:testing"

@(private = "file")
expect_text :: proc(t: ^testing.T, gb: ^Gap_Buffer, want: string, loc := #caller_location) {
	l, r := as_string_parts(gb)
	testing.expect_value(t, fmt.tprintf("%s%s", l, r), want, loc)
}

@(private = "file")
expect_parts :: proc(
	t: ^testing.T,
	gb: ^Gap_Buffer,
	want_l, want_r: string,
	loc := #caller_location,
) {
	l, r := as_string_parts(gb)
	testing.expect_value(t, l, want_l, loc)
	testing.expect_value(t, r, want_r, loc)
}

@(private = "file")
expect_cursor :: proc(
	t: ^testing.T,
	gb: ^Gap_Buffer,
	want_line, want_col: int,
	loc := #caller_location,
) {
	line, col := cursor_line_col(gb)
	testing.expect_value(t, line, want_line, loc)
	testing.expect_value(t, col, want_col, loc)
}


@(test)
test_empty :: proc(t: ^testing.T) {
	gb := make_gap_buffer(16)
	defer destroy_gap_buffer(&gb)

	expect_parts(t, &gb, "", "")
	testing.expect_value(t, gb.start, 0)
	testing.expect_value(t, gb.end, 16)
}

@(test)
test_insert_string_middle :: proc(t: ^testing.T) {
	gb := make_gap_buffer(16)
	defer destroy_gap_buffer(&gb)

	insert(&gb, 0, "0123456789")
	insert(&gb, 5, "ab")
	expect_parts(t, &gb, "01234ab", "56789")
}

@(test)
test_insert_string_front :: proc(t: ^testing.T) {
	gb := make_gap_buffer(16)
	defer destroy_gap_buffer(&gb)

	insert(&gb, 0, "6789")
	insert(&gb, 0, "012345")
	expect_parts(t, &gb, "012345", "6789")
}

@(test)
test_insert_past_end_appends :: proc(t: ^testing.T) {
	gb := make_gap_buffer(16)
	defer destroy_gap_buffer(&gb)

	insert(&gb, 0, "0123")
	insert(&gb, 100, "45")
	expect_parts(t, &gb, "012345", "")
}

@(test)
test_insert_char :: proc(t: ^testing.T) {
	gb := make_gap_buffer(16)
	defer destroy_gap_buffer(&gb)

	insert(&gb, 0, "0123456789")
	insert(&gb, 3, u8('a'))
	expect_parts(t, &gb, "012a", "3456789")
}

@(test)
test_insert_slice :: proc(t: ^testing.T) {
	gb := make_gap_buffer(16)
	defer destroy_gap_buffer(&gb)

	insert(&gb, 0, "0123")
	bytes := []u8{'x', 'y'}
	insert(&gb, 2, bytes)
	expect_parts(t, &gb, "01xy", "23")
}

@(test)
test_insert_rune_multibyte :: proc(t: ^testing.T) {
	gb := make_gap_buffer(16)
	defer destroy_gap_buffer(&gb)

	insert(&gb, 0, "ab")
	insert(&gb, 1, 'é') // 2 bytes
	insert(&gb, 3, '世') // 3 bytes
	insert(&gb, 6, '🙂') // 4 bytes
	expect_text(t, &gb, "aé世🙂b")
	testing.expect_value(t, gb.start, 10)
}

@(test)
test_shift_gap_preserves_text :: proc(t: ^testing.T) {
	gb := make_gap_buffer(16)
	defer destroy_gap_buffer(&gb)

	insert(&gb, 0, "0123456789")

	shift_gap_to(&gb, 3)
	expect_parts(t, &gb, "012", "3456789")

	shift_gap_to(&gb, 8)
	expect_parts(t, &gb, "01234567", "89")

	shift_gap_to(&gb, 0)
	expect_parts(t, &gb, "", "0123456789")

	shift_gap_to(&gb, 100) // clamped to end of text
	expect_parts(t, &gb, "0123456789", "")
}

@(test)
test_remove_middle :: proc(t: ^testing.T) {
	gb := make_gap_buffer(16)
	defer destroy_gap_buffer(&gb)

	insert(&gb, 0, "0123456789")
	remove(&gb, 2, 3)
	expect_parts(t, &gb, "01", "56789")
}

@(test)
test_remove_front_and_end :: proc(t: ^testing.T) {
	gb := make_gap_buffer(16)
	defer destroy_gap_buffer(&gb)

	insert(&gb, 0, "0123456789")
	remove(&gb, 0, 2)
	expect_text(t, &gb, "23456789")
	remove(&gb, 6, 2)
	expect_text(t, &gb, "234567")
}

@(test)
test_remove_past_end_clamps :: proc(t: ^testing.T) {
	gb := make_gap_buffer(16)
	defer destroy_gap_buffer(&gb)

	insert(&gb, 0, "0123456789")
	remove(&gb, 7, 100)
	expect_parts(t, &gb, "0123456", "")

	remove(&gb, 100, 5) // removing past the text is a no-op
	expect_text(t, &gb, "0123456")
}

@(test)
test_remove_then_insert :: proc(t: ^testing.T) {
	gb := make_gap_buffer(16)
	defer destroy_gap_buffer(&gb)

	insert(&gb, 0, "hello world")
	remove(&gb, 6, 5)
	insert(&gb, 6, "odin")
	expect_text(t, &gb, "hello odin")
}

@(test)
test_grow_appending :: proc(t: ^testing.T) {
	gb := make_gap_buffer(16)
	defer destroy_gap_buffer(&gb)

	insert(&gb, 0, "0123456789")
	insert(&gb, 10, "abcdefghij")
	expect_text(t, &gb, "0123456789abcdefghij")
	testing.expect(t, len(gb.buf) >= 20)
}

@(test)
test_grow_inserting_in_middle :: proc(t: ^testing.T) {
	gb := make_gap_buffer(16)
	defer destroy_gap_buffer(&gb)

	insert(&gb, 0, "0123456789")
	shift_gap_to(&gb, 4) // gap in the middle when growth happens
	insert(&gb, 5, "abcdefghij")
	expect_text(t, &gb, "01234abcdefghij56789")
}

@(test)
test_grow_large_single_insert :: proc(t: ^testing.T) {
	gb := make_gap_buffer(4)
	defer destroy_gap_buffer(&gb)

	insert(&gb, 0, "ab")
	big := "0123456789abcdefghijklmnopqrstuvwxyz" // bigger than 2x capacity
	insert(&gb, 1, big)
	expect_text(t, &gb, "a0123456789abcdefghijklmnopqrstuvwxyzb")
}

@(test)
test_grow_char_by_char :: proc(t: ^testing.T) {
	gb := make_gap_buffer(1)
	defer destroy_gap_buffer(&gb)

	want := "the quick brown fox jumps over the lazy dog"
	for i in 0 ..< len(want) {
		insert(&gb, i, want[i])
	}
	expect_text(t, &gb, want)
}

@(test)
test_insert_string :: proc(t: ^testing.T) {
	gb := make_gap_buffer(16)
	defer destroy_gap_buffer(&gb)

	insert(&gb, 0, "0123456789")
	l, r := as_string_parts(&gb)
	testing.expect_value(t, l, "0123456789")
	testing.expect_value(t, r, "")
}

@(test)
test_insert_rune :: proc(t: ^testing.T) {
	gb := make_gap_buffer(16)
	defer destroy_gap_buffer(&gb)
	insert(&gb, 0, "0123456789")

	insert(&gb, 3, 'a')

	l, r := as_string_parts(&gb)
	testing.expect_value(t, l, "012a")
	testing.expect_value(t, r, "3456789")
}

@(test)
test_cursor_up_down :: proc(t: ^testing.T) {
	gb := make_gap_buffer(16)
	defer destroy_gap_buffer(&gb)

	insert(&gb, 0, "héllo\nhi\nworld")
	// cursor is at the end: after "world"
	cursor_up(&gb) // "hi" is shorter: stop at its end
	expect_parts(t, &gb, "héllo\nhi", "\nworld")
	cursor_up(&gb) // column 2 on the first line, after "hé"
	expect_parts(t, &gb, "hé", "llo\nhi\nworld")
	cursor_up(&gb) // first line: nothing happens
	expect_parts(t, &gb, "hé", "llo\nhi\nworld")
	cursor_down(&gb)
	cursor_down(&gb)
	expect_parts(t, &gb, "héllo\nhi\nwo", "rld")
	cursor_down(&gb) // last line: nothing happens
	expect_parts(t, &gb, "héllo\nhi\nwo", "rld")
}

@(test)
test_load_text :: proc(t: ^testing.T) {
	gb := make_gap_buffer(4) // smaller than the text, so load_text has to grow
	defer destroy_gap_buffer(&gb)

	file: string : "hello\nworld\nhello\nhello world\nhello world\nhello world\nhello world\nhello world"

	insert(&gb, 0, "old")
	load_text(&gb, file)

	expect_parts(t, &gb, "", file)
	testing.expect_value(t, gb.start, 0)

	load_text(&gb, nil)
	expect_parts(t, &gb, "", "")
}


@(test)
test_write_to :: proc(t: ^testing.T) {
	sb := strings.builder_make_none()
	defer strings.builder_destroy(&sb)

	gb := make_gap_buffer(4)
	defer destroy_gap_buffer(&gb)

	file: string : "some content\n on multiple\nlines"
	load_text(&gb, file)

	testing.expect_value(t, write_to(&gb, strings.to_writer(&sb)), nil)
	testing.expect_value(t, strings.to_string(sb), file)

}


@(test)
test_cursor_line_col :: proc(t: ^testing.T) {
	Case :: struct {
		input:     string,
		line, col: int,
	}

	gb := make_gap_buffer(16)
	defer destroy_gap_buffer(&gb)

	cases := []Case {
		{"", 0, 0},
		{input = "abc", line = 0, col = 3},
		{"abc\n", 1, 0},
		{"ab\ncd\nef", 2, 2},
		{"héllo", 0, 5}, // é is 2 bytes
		{"a\n世界", 1, 2}, //世界 > 3 bytes
	}
	for c in cases {
		insert(&gb, 0, c.input)
		expect_cursor(t, &gb, c.line, c.col)
		remove(&gb, 0, len(c.input))
	}
	load_text(&gb, "ab\ncd")
	expect_cursor(t, &gb, 0, 0)
	remove(&gb, 0, len("ab\ncd"))

	insert(&gb, 0, "héllo\nhi")
	expect_cursor(t, &gb, 1, 2)
	cursor_up(&gb)
	expect_cursor(t, &gb, 0, 2)
}

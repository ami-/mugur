package main
import "core:io"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"

Pos :: int

Gap_Buffer :: struct {
	buf:       []u8,
	start:     Pos,
	end:       Pos,
	allocator: mem.Allocator,
}

make_gap_buffer :: proc(n_bytes: int, allocator := context.allocator) -> Gap_Buffer {
	gb := Gap_Buffer {
		buf       = make([]u8, n_bytes, allocator),
		start     = 0,
		end       = n_bytes,
		allocator = allocator,
	}
	return gb
}
destroy_gap_buffer :: proc(gb: ^Gap_Buffer) {
	delete(gb.buf, gb.allocator)
}

//resize buffer
check_gap_size :: proc(gb: ^Gap_Buffer, required: int) {
	gap_len := gb.end - gb.start
	if gap_len < required {
		text_len := len(gb.buf) - gap_len
		shift_gap_to(gb, text_len)
		new_buf := make([]u8, max(text_len + required, 2 * len(gb.buf)), gb.allocator)
		copy_slice(new_buf, gb.buf[:gb.start])
		delete(gb.buf, gb.allocator)
		gb.buf = new_buf
		gb.end = len(gb.buf)

	}
}


shift_gap_to :: proc(gb: ^Gap_Buffer, pos: Pos) {
	gap_len := gb.end - gb.start
	cursor := min(pos, len(gb.buf) - gap_len)

	if cursor == gb.start {
		//nothing to do
		return
	}

	if gb.start < cursor {
		// gap before cursor
		// [12]            [3456789]
		//--------|-----------------
		// [123456]------------[789]
		delta := cursor - gb.start
		mem.copy(&gb.buf[gb.start], &gb.buf[gb.end], delta)
		gb.start += delta
		gb.end += delta
	} else if gb.start > cursor {
		// gap after cursor
		// [123456]------------[789]
		//----|---------------------
		// [12]            [3456789]
		delta := gb.start - cursor
		mem.copy(&gb.buf[gb.end - delta], &gb.buf[gb.start - delta], delta)
		gb.start -= delta
		gb.end -= delta
	}

}

insert :: proc {
	insert_char,
	insert_rune,
	insert_slice,
	insert_string,
}

insert_char :: proc(gb: ^Gap_Buffer, pos: Pos, ch: u8) {
	check_gap_size(gb, 1)
	shift_gap_to(gb, pos)
	gb.buf[gb.start] = ch
	gb.start += 1
}
insert_rune :: proc(gb: ^Gap_Buffer, pos: Pos, r: rune) {
	bytes, n := utf8.encode_rune(r)
	insert_slice(gb, pos, bytes[:n])

}
insert_slice :: proc(gb: ^Gap_Buffer, pos: Pos, bytes: []u8) {
	check_gap_size(gb, len(bytes))
	shift_gap_to(gb, pos)
	copy_slice(gb.buf[gb.start:], bytes)
	gb.start += len(bytes)
}
insert_string :: proc(gb: ^Gap_Buffer, pos: Pos, str: string) {
	insert_slice(gb, pos, transmute([]u8)str)
}

remove :: proc(gb: ^Gap_Buffer, pos: Pos, count: int) {
	shift_gap_to(gb, pos)
	gb.end = min(gb.end + count, len(gb.buf))
}

load_text :: proc {
	load_string,
	load_slice,
}

load_string :: proc(gb: ^Gap_Buffer, str: string) {
	load_slice(gb, transmute([]u8)str)
}

load_slice :: proc(gb: ^Gap_Buffer, bytes: []byte) {
	//before:  [old text....|------gap------|...more old]
	//after:   [-------------gap------------|new text...]

	initial_gap :: 64
	if len(gb.buf) < len(bytes) + initial_gap {
		new_buf := make([]u8, len(bytes) + max(initial_gap, len(bytes)), gb.allocator)
		delete(gb.buf, gb.allocator)
		gb.buf = new_buf
	}
	gb.start = 0
	gb.end = len(gb.buf) - len(bytes)
	copy(gb.buf[gb.end:], bytes)
}

@(private = "package")
as_string_parts :: proc(gb: ^Gap_Buffer) -> (left: string, right: string) {
	left = string(gb.buf[:gb.start])
	right = string(gb.buf[gb.end:])
	return
}

text_len :: proc(gb: ^Gap_Buffer) -> int {
	return len(gb.buf) - (gb.end - gb.start)
}

as_text :: proc(gb: ^Gap_Buffer, allocator := context.temp_allocator) -> string {
	l, r := as_string_parts(gb)
	return strings.concatenate({l, r}, allocator)
}

byte_at :: proc(gb: ^Gap_Buffer, pos: Pos) -> u8 {
	return gb.buf[pos] if pos < gb.start else gb.buf[pos + gb.end - gb.start]
}

line_start :: proc(gb: ^Gap_Buffer, pos: Pos) -> Pos {
	p := pos
	for p > 0 && byte_at(gb, p - 1) != '\n' {
		p -= 1
	}
	return p
}

line_end :: proc(gb: ^Gap_Buffer, pos: Pos) -> Pos {
	p := pos
	for p < text_len(gb) && byte_at(gb, p) != '\n' {
		p += 1
	}
	return p
}

backspace :: proc(gb: ^Gap_Buffer) {
	l, _ := as_string_parts(gb)
	_, size := utf8.decode_last_rune_in_string(l)
	remove(gb, gb.start - size, size)
}
cursor_left :: proc(gb: ^Gap_Buffer) {
	l, _ := as_string_parts(gb)
	_, size := utf8.decode_last_rune_in_string(l)
	shift_gap_to(gb, gb.start - size)
}

cursor_right :: proc(gb: ^Gap_Buffer) {
	_, r := as_string_parts(gb)
	_, size := utf8.decode_rune_in_string(r)
	shift_gap_to(gb, gb.start + size)
}

// UTF-8 continuation bytes look like 10xxxxxx
is_continuation :: proc(b: u8) -> bool {
	return b & 0xC0 == 0x80
}

// number of runes in text positions [from, to)
runes_between :: proc(gb: ^Gap_Buffer, from, to: Pos) -> int {
	n := 0
	for i in from ..< to {
		if !is_continuation(byte_at(gb, i)) {
			n += 1
		}
	}
	return n
}

// position n runes after `from`, never past `limit`
skip_runes :: proc(gb: ^Gap_Buffer, from: Pos, n: int, limit: Pos) -> Pos {
	p := from
	for _ in 0 ..< n {
		if p >= limit {
			break
		}
		p += 1
		for p < limit && is_continuation(byte_at(gb, p)) {
			p += 1
		}
	}
	return p
}

cursor_up :: proc(gb: ^Gap_Buffer, col: int) {
	start := line_start(gb, gb.start)
	if start == 0 {
		return // already on the first line
	}
	prev_start := line_start(gb, start - 1)
	shift_gap_to(gb, skip_runes(gb, prev_start, col, start - 1))
}

cursor_down :: proc(gb: ^Gap_Buffer, col: int) {
	end := line_end(gb, gb.start)
	if end == text_len(gb) {
		return // already on the last line
	}
	next_start := end + 1
	shift_gap_to(gb, skip_runes(gb, next_start, col, line_end(gb, next_start)))
}

cursor_line_col :: proc(gb: ^Gap_Buffer) -> (line, col: int) {
	l := string(gb.buf[:gb.start])
	line = strings.count(l, "\n")
	col = strings.rune_count(l[strings.last_index_byte(l, '\n') + 1:])
	return
}

@(require_results)
write_to :: proc(gb: ^Gap_Buffer, w: io.Writer) -> io.Error {
	l, r := as_string_parts(gb)
	io.write_string(w, l) or_return
	io.write_string(w, r) or_return
	return nil
}

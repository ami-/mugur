package editor

Editor :: struct {
	// the text buffer
	buf:         Gap_Buffer,

	// scroll position
	line_offset: int,
	col_offset:  int,
	want_col:    int,
	status:      string,
}


@(private)
EDITOR_INIT_CAP :: 64


make_editor :: proc() -> Editor {
	return Editor{buf = make_gap_buffer(EDITOR_INIT_CAP)}
}

destroy_editor :: proc(e: ^Editor) {
	destroy_gap_buffer(&e.buf)
}

update :: proc(ed: ^Editor, ev: Event) {
	gb := &ed.buf
	switch e in ev {
	case Key_Event:
		switch e.key {
		case .Up:
			cursor_up(gb, ed.want_col)
		case .Down:
			cursor_down(gb, ed.want_col)
		case .Left:
			cursor_left(gb)
		case .Right:
			cursor_right(gb)
		case .Enter:
			insert(gb, gb.start, u8('\n'))
		case .Backspace:
			backspace(gb)
		case .Escape:
			ed.status = "Escape pressed"
		case .Char:
			if e.mods == {} {
				insert(gb, gb.start, e.r)
			}
		}
		//update want_col with new position
		if e.key != .Up && e.key != .Down && e.key != .Escape {
			_, ed.want_col = cursor_line_col(gb)
		}
		if e.key != .Escape {
			ed.status = ""
		}
	}
}

scroll :: proc(ed: ^Editor, rows, cols, cursor_row, cursor_col: int) {
	if cursor_row < ed.line_offset {
		ed.line_offset = cursor_row
	}
	if cursor_row >= ed.line_offset + rows {
		ed.line_offset = cursor_row - rows + 1
	}
	if cursor_col < ed.col_offset {
		ed.col_offset = max(0, cursor_col - cols / 2)
	}
	if cursor_col >= ed.col_offset + cols {
		ed.col_offset = cursor_col - cols + 1
	}
}

visible_part :: proc(line: string, offset, width: int) -> string {
	n := 0
	lstart, lend := len(line), len(line)
	for _, idx in line {
		if n == offset {
			lstart = idx
		}
		if n == offset + width {
			lend = idx
			break
		}
		n += 1
	}
	return line[lstart:lend]
}

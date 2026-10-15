package main

Editor :: struct {
	// the text buffer
	buf:         Gap_Buffer,

	// scroll position
	line_offset: int,
	col_offset:  int,

	// in vertical movement, keep track of original starting point
	want_col:    int,
	status:      string,
}

EDITOR_QUIT_MSG :: "Press CTRL+'q' to exit"

@(private)
EDITOR_INIT_CAP :: 64
make_editor :: proc() -> Editor {
	return Editor {
		buf    = make_gap_buffer(EDITOR_INIT_CAP),
		//status
		status = EDITOR_QUIT_MSG,
	}
}

destroy_editor :: proc(e: ^Editor) {
	destroy_gap_buffer(&e.buf)
}

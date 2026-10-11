package main

import "core:fmt"
import "core:strings"
import "core:terminal/ansi"

// Helpers that append escape sequences to a frame builder.
// Constants come from core:terminal/ansi; see
// https://en.wikipedia.org/wiki/ANSI_escape_code

// rows and columns start at 1
move_to :: proc(b: ^strings.Builder, row, col: int) {
	fmt.sbprintf(b, ansi.CSI + "%d;%d" + ansi.CUP, row, col)
}

clear_screen :: proc(b: ^strings.Builder) {
	strings.write_string(b, ansi.CSI + "2" + ansi.ED)
}

invert_colors :: proc(b: ^strings.Builder) {
	strings.write_string(b, ansi.CSI + ansi.INVERT + ansi.SGR)
}

reset_style :: proc(b: ^strings.Builder) {
	strings.write_string(b, ansi.CSI + ansi.RESET + ansi.SGR)
}

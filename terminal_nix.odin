#+build linux
package main

import "core:sync"
import "core:sys/linux"
import psx "core:sys/posix"
import "core:terminal/ansi"

@(private = "file")
orig_mode: psx.termios

@(private = "file")
raw_mode: psx.termios

//set by SIGCONT handler, read and cleared by main loop
resumed: bool

enable_raw_mode :: proc() {
	// Save original mode
	res := psx.tcgetattr(psx.STDIN_FILENO, &orig_mode)
	assert(res == .OK)

	raw_mode = orig_mode

	// local flags
	raw_mode.c_lflag -= {
		.ECHO, //disable character echo
		.ICANON, //disable input one per line (line buffering)
		//.ISIG, //disable Ctrl+C kill, Ctrl+Z suspend, Ctrl+\ quit (core dump)
		.IEXTEN, //disable Ctrl + V (insert next key literally)
	}

	//input flags
	raw_mode.c_iflag -= {
		.IXON, //disable Ctrl+S/Ctrl+Q pause and resume output
		//.ICRNL turns \r into \n
		.BRKINT, //disable break signal
		.INPCK, //disable parity checks cutting bytes to 7 bits
		.ISTRIP, //disabling it allows utf-8 to arrive intact
	}

	raw_mode.c_cc[.VMIN] = 0 // return even if no bytes arrived...
	raw_mode.c_cc[.VTIME] = 1 // ...after waiting up to 100 ms (VTIME is in tenths of a second)

	res = psx.tcsetattr(psx.STDIN_FILENO, .TCSANOW, &raw_mode)
	assert(res == .OK)

	job_control_handlers()
}

disable_raw_mode :: proc "c" () {
	psx.tcsetattr(psx.STDIN_FILENO, .TCSANOW, &orig_mode)
}

Winsize :: struct {
	ws_row:    u16,
	ws_col:    u16,
	ws_xpixel: u16,
	ws_ypixel: u16,
}

// TIOCGWINSZ value is typically 0x5413 on Linux/macOS
TIOCGWINSZ :: 0x5413

get_terminal_size :: proc() -> (rows, cols: int, ok: bool) {
	ws: Winsize
	// Call ioctl on stdout file descriptor
	res := linux.ioctl(psx.STDOUT_FILENO, linux.TIOCGWINSZ, uintptr(&ws))
	if res < 0 {
		return 0, 0, false
	}
	return int(ws.ws_row), int(ws.ws_col), true
}


// install signal handlers for suspend(CTRL+Z) and resume
@(private = "file")
job_control_handlers :: proc() {
	sa: psx.sigaction_t
	sa.sa_flags = {
		.RESTART, // Cause certain functions to become restartable.
	}
	// when doing CTRL + Z to stop, SIGTSTP is sent
	sa.sa_handler = on_suspend
	psx.sigaction(.SIGTSTP, &sa, nil)

	// when doing fg SIGCONT is sent to wake up
	sa.sa_handler = on_resume
	psx.sigaction(.SIGCONT, &sa, nil)
}

//signal safe write, no context needed
@(private = "file")
write_str :: proc "contextless" (s: string) {
	psx.write(psx.STDOUT_FILENO, raw_data(s), len(s))
}

// CTRL+Z: give terminal back to shell then stop
@(private = "file")
on_suspend :: proc "c" (sig: psx.Signal) {
	//leave alternate screen
	write_str(ansi.CSI + ansi.DECASB_EXIT)
	psx.tcsetattr(psx.STDIN_FILENO, .TCSANOW, &orig_mode)
	psx.kill(psx.getpid(), .SIGSTOP) //SIGSTOP can't be caught, so this really stops
}

// fg: take terminal back
@(private = "file")
on_resume :: proc "c" (sig: psx.Signal) {
	psx.tcsetattr(psx.STDIN_FILENO, .TCSANOW, &raw_mode)
	// back to alternate screen
	write_str(ansi.CSI + ansi.DECASB_ENTER)
	sync.atomic_store(&resumed, true) //main loop redraws
}

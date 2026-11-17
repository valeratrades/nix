/// (columns, rows) of the terminal on `fd`, if it is one.
pub fn winsize(fd: libc::c_int) -> Option<(usize, usize)> {
	let mut ws: libc::winsize = unsafe { std::mem::zeroed() };
	(unsafe { libc::ioctl(fd, libc::TIOCGWINSZ, &mut ws) } == 0 && ws.ws_col > 0).then_some((ws.ws_col as usize, ws.ws_row as usize))
}

use std::{os::unix::process::CommandExt, process::Command, time::Duration};

/// A bare pty answers no terminal queries, and a TUI may block on one (nvim waits 100ms on DSR); a real terminal replies in <1ms.
const REPLIES: [(&[u8], &[u8]); 3] = [(b"\x1b[5n", b"\x1b[0n"), (b"\x1b]11;?", b"\x1b]11;rgb:1e1e/1e1e/2e2e\x1b\\"), (b"\x1b[c", b"\x1b[?62;22c")];

/// A child on its own pty, as its session leader.
pub struct Pty {
	pid: libc::pid_t,
	master: libc::c_int,
}
impl Pty {
	pub fn spawn(mut cmd: Command) -> Self {
		let ws = libc::winsize { ws_row: 50, ws_col: 200, ws_xpixel: 0, ws_ypixel: 0 };
		let mut master = -1;
		match unsafe { libc::forkpty(&mut master, std::ptr::null_mut(), std::ptr::null(), &ws) } {
			-1 => panic!("forkpty: {}", std::io::Error::last_os_error()),
			0 => {
				eprintln!("exec {cmd:?}: {}", cmd.exec());
				unsafe { libc::_exit(127) }
			}
			pid => Self { pid, master },
		}
	}

	/// Drains what the child wrote within `timeout`, answering its terminal queries; `false` once it has closed the pty.
	pub fn pump(&self, timeout: Duration) -> bool {
		let mut pfd = libc::pollfd { fd: self.master, events: libc::POLLIN, revents: 0 };
		match unsafe { libc::poll(&mut pfd, 1, timeout.as_millis() as libc::c_int) } {
			0 => return true,
			n if n < 0 => {
				let e = std::io::Error::last_os_error();
				assert_eq!(e.kind(), std::io::ErrorKind::Interrupted, "poll: {e}");
				return true;
			}
			_ => {}
		}
		let mut buf = vec![0u8; 65536];
		let n = unsafe { libc::read(self.master, buf.as_mut_ptr().cast(), buf.len()) };
		if n <= 0 {
			return false;
		}
		let buf = &buf[..n as usize];
		for (query, reply) in REPLIES {
			if buf.windows(query.len()).any(|w| w == query) {
				let n = unsafe { libc::write(self.master, reply.as_ptr().cast(), reply.len()) };
				assert_eq!(n, reply.len() as isize, "pty write: {}", std::io::Error::last_os_error());
			}
		}
		true
	}

	/// TERM to its whole process group, which reaps whatever it spawned too.
	pub fn kill(&self) {
		unsafe { libc::killpg(self.pid, libc::SIGTERM) };
	}

	pub fn wait(&self) {
		let mut status = 0;
		assert_eq!(unsafe { libc::waitpid(self.pid, &mut status, 0) }, self.pid, "waitpid: {}", std::io::Error::last_os_error());
	}
}

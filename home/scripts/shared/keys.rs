//! mpv-style foreground controls, for scripts to `#[path]`-import; needs `crossterm` in the importer's deps.

use crossterm::event::{self, Event, KeyCode, KeyModifiers};
use std::{
    io::{self, IsTerminal, Write},
    time::{Duration, Instant},
};

pub enum Key {
    TogglePause,
    Quit,
}

/// Terminal is in raw mode while this lives.
pub struct Keys(());

impl Keys {
    /// `None` when not attached to a terminal.
    pub fn grab() -> io::Result<Option<Self>> {
        if !(io::stdin().is_terminal() && io::stdout().is_terminal()) {
            return Ok(None);
        }
        crossterm::terminal::enable_raw_mode()?;
        println!("Space: pause/play, Ctrl-C: quit\r");
        Ok(Some(Self(())))
    }

    /// raw mode delivers Ctrl-C as a key, not SIGINT
    pub fn next_within(&self, dur: Duration) -> io::Result<Option<Key>> {
        let end = Instant::now() + dur;
        loop {
            if !event::poll(end.saturating_duration_since(Instant::now()))? {
                return Ok(None);
            }
            if let Event::Key(k) = event::read()? {
                match k.code {
                    KeyCode::Char(' ') => return Ok(Some(Key::TogglePause)),
                    KeyCode::Char('c') if k.modifiers.contains(KeyModifiers::CONTROL) => return Ok(Some(Key::Quit)),
                    _ => {}
                }
            }
        }
    }
}

impl Drop for Keys {
    fn drop(&mut self) {
        crossterm::terminal::disable_raw_mode().expect("was enabled by grab");
        print!("\r\n"); // off the status line
        io::stdout().flush().expect("stdout is the terminal grab checked");
    }
}

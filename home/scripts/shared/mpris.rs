//! Minimal MPRIS player, so media keys (sway's play_pause.sh, playerctl) reach our scripts like they reach mpv. Needs `zbus` in the importer's deps.

use zbus::{blocking::Connection, fdo, interface};

struct Root(&'static str);

#[interface(name = "org.mpris.MediaPlayer2")]
impl Root {
    fn raise(&self) {}
    fn quit(&self) {}
    #[zbus(property)]
    fn can_quit(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn can_raise(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn has_track_list(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn identity(&self) -> String {
        self.0.to_string()
    }
    #[zbus(property)]
    fn supported_uri_schemes(&self) -> Vec<String> {
        vec![]
    }
    #[zbus(property)]
    fn supported_mime_types(&self) -> Vec<String> {
        vec![]
    }
}

type IsPaused = Box<dyn Fn() -> bool + Send + Sync>;
type SetPaused = Box<dyn Fn(bool) -> Result<(), String> + Send + Sync>;

struct Player {
    is_paused: IsPaused,
    set_paused: SetPaused,
}

impl Player {
    fn set(&self, paused: bool) -> fdo::Result<()> {
        (self.set_paused)(paused).map_err(fdo::Error::Failed)
    }
}

#[interface(name = "org.mpris.MediaPlayer2.Player")]
impl Player {
    fn play(&self) -> fdo::Result<()> {
        self.set(false)
    }
    fn pause(&self) -> fdo::Result<()> {
        self.set(true)
    }
    fn play_pause(&self) -> fdo::Result<()> {
        self.set(!(self.is_paused)())
    }
    #[zbus(property)]
    fn playback_status(&self) -> String {
        match (self.is_paused)() {
            true => "Paused",
            false => "Playing",
        }
        .to_string()
    }
    #[zbus(property)]
    fn can_play(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_pause(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_control(&self) -> bool {
        true
    }
}

/// Served while the returned connection lives.
pub fn serve(
    name: &'static str,
    is_paused: impl Fn() -> bool + Send + Sync + 'static,
    set_paused: impl Fn(bool) -> Result<(), String> + Send + Sync + 'static,
) -> zbus::Result<Connection> {
    zbus::blocking::connection::Builder::session()?
        .name(format!("org.mpris.MediaPlayer2.{name}.instance{}", std::process::id()))?
        .serve_at("/org/mpris/MediaPlayer2", Root(name))?
        .serve_at(
            "/org/mpris/MediaPlayer2",
            Player {
                is_paused: Box::new(is_paused),
                set_paused: Box::new(set_paused),
            },
        )?
        .build()
}

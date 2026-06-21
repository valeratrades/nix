{
  # speech-dispatcher gets pulled in transitively (at-spi/TTS) and its socket
  # auto-activates on any a11y poke, forking ~12 output modules; the ones whose
  # engine isn't installed exit unreaped -> permanent zombies. We use no TTS, so
  # mask both units. ponytail: drop this file if a screen reader is ever wanted.
  systemd.user.services.speech-dispatcher.enable = false;
  systemd.user.sockets.speech-dispatcher.enable = false;
}

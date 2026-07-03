{
  filter_mode_shell_up_key_binding = "directory"; # up-key search only searches in current dir
  sync.records = true;
  enter_accept = true;
  # commands starting with these prefixes are never recorded
  history_filter = map (p: "^${p}") [
    "tg"
  ];
}

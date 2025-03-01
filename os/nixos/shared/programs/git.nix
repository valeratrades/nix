{ userHome
, ...
}:
let
  _ = builtins.trace "TRACE: userHome: ${userHome}"; # dbg
in
{
  #dbg
  programs.git = {
    enable = true;
  };
}

{ inputs
, config
, lib
, ...
}:
{
  security.sudo = builtins.trace "DEBUG: loading `machines` module" {
    execWheelOnly = lib.mkForce false;
    # allow for running sudo when connected via ssh
    #extraConfig = ''
    #  	Defaults env_keep += "SSH_AUTH_SOCK"
    #  		'';
  };

  imports = [
    ./fhs-compat.nix
  ];
}

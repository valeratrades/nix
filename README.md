# Installation
NB: should have your correct `hardware-configuration.nix` at `/etc/nixos/hardware-configuration.nix`. In my setup hosts normally include their associated `hardware-configuration.nix` files, but they are used as a backup in case `/etc/nixos/hardware-configuration.nix` is not found.

Set the `INSTALL_PATH`, then run
```sh
sh << 'EOF'
INSTALL_PATH="..."
if [ "$INSTALL_PATH" = "..." ]; then
    echo "set the INSTALL_PATH to the target installation path, then rerun the command"
    return 1
fi
mkdir -p "$(dirname "$INSTALL_PATH")" && \
git clone --depth=1 https://github.com/valeratrades/nix "$INSTALL_PATH" && \
cd "$INSTALL_PATH"
EOF
```


## Reqs
~/s/g/private/credentials.fish file with following variables set:
```fish
$GITHUB_KEY
```

## Manual adjustments
Currently:
- git config in ./os/configuration.nix must be adjusted for the correct username and email

# Usage
```sh
fhs
```

Spawns an fhs-compatible shell


# Dev
Currently config is impure. For possibility of reversion, all known places that introduce impurities are marked with `#IMPURE`

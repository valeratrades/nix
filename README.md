# Installation
NB: set the `INSTALL_PATH` before running
```sh
sh << 'EOF'
INSTALL_PATH="..."
if [ "$INSTALL_PATH" = "..." ]; then
    echo "set the INSTALL_PATH to the target installation path, then rerun the command"
    return 1
fi
mkdir -p "$(dirname "$INSTALL_PATH")" && \
git clone --depth=1 https://github.com/valeratrades/nix "$INSTALL_PATH" && \
cd "$INSTALL_PATH" && \
sudo mkdir -p /usr/share/X11/xkb/symbols && \
sudo cp -r ./home/config/xkb_symbols/* /usr/share/X11/xkb/symbols/
EOF
```


## Reqs
~/s/g/private/credentials.fish file with following variables set:
```fish
$GITHUB_KEY
```

## Manual adjustments
git config in ./os/configuration.nix must be adjusted for the correct username and email

# Usage
```sh
fhs
```

Spawns an fhs-compatible shell


# Dev
Currently config is impure. For possibility of reversion, all known places that introduce impurities are marked with `#IMPURE`

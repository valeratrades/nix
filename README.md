My dots

## Reqs
### creds
~/s/g/private/credentials.fish file with following variables set:
```fish
$GITHUB_KEY
```

### hardware-configuration
Should have your correct `hardware-configuration.nix` at `/etc/nixos/hardware-configuration.nix`. In my setup hosts normally include their associated `hardware-configuration.nix` files, but they are used as a backup in case `/etc/nixos/hardware-configuration.nix` is not found.

### config location
This configuration **MUST** be located in `~/nix`, (because I didn't find a way to get the actual positions of the files in which the code being ran is written at runtime, so many things assume `~/nix` to be the config root.


## Installation
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



### Manual adjustments
Introduced `MANUAL` keyword in config next to things that require manual adjustments and cannot be proceduralized. Do not guarantee surjectivity.

Currently:
- git config in ./os/configuration.nix must be adjusted for the correct username and email

## Usage
```sh
fhs
```

Spawns an fhs-compatible shell

### Server deployment
```sh
sudo nixos-rebuild switch -I nixos-config=/home/v/nix/os/nixos/server-configuration.nix
```


## Dev
Currently config is impure. For possibility of reversion, all known places that introduce impurities are marked with `#IMPURE`

## Other
### Philosophy
- No convenience optimisations should be made for suboptimal actions/behaviors/patterns. For example, I will never have `Spotify` pinned to a designated workspace, as it is desirable to maximize friction around these.

- Declarative > Situational. That's the reason I don't end up using shortcuts for switching panes. All my tools must be designed with this in mind: it's fine if more work is required for the same action, as long as this leads to it being [pure](<https://en.wikipedia.org/wiki/Pure_function>); and then all situational, impure, shortcuts should not be introduced at all, as it only convolutes the manpage. The largest change in behavior this should prompt: getting rid of all toggles, unless it is meant to be evoked exclusively via keybind, (meaning can't add <command> on / <command> off), and there is a keybind deficit.

- all shortcuts, scripts and tools must be 5std reliable. If they fail more often, the default should be used. Indexing some but not much for how important the tool is.

#### Cli
Target length for general aliases is 2 characters, if they are important enough.
One-letter cases are mostly reserved for custom scripts, local to the project, eg: commands initialized when I `cs` into a directory with `run.sh` in it.

#### Data Storage
Each thing should be stored based on how it will be **used**, **not** on how it was **created**.

For example, a PA screenshot should not go to say [~/Images/Screenshots] nor even to [~/Images/Screenshots/PA/], but to say [~/trading/strats/relevant/strat/path/], along all the other considerations on that strat (.md, .rnote, etc; maybe even some scripts)
Same thing applies to notes (don't make folders for a book, - sort ideas out into correct places in the knowledge-base or discard).

# New pc setup steps
- disable default F key functions
- turn off Secure Boot

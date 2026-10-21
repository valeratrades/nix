set cli_translate "$HOME/s/help_scripts/cli_translate.py"
function ttf; $cli_translate -f $argv; end
function tte; $cli_translate -e $argv; end
function ttr; $cli_translate -r $argv; end

# Compatibility aliases for Chrome translate shortcuts
function tef; $cli_translate -f $argv; end
function trf; $cli_translate -f $argv; end
function tfe; $cli_translate -e $argv; end
function tre; $cli_translate -e $argv; end
function ter; $cli_translate -r $argv; end
function tfr; $cli_translate -r $argv; end

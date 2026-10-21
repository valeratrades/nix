function za --wraps zathura; zathura $argv; end
function zp --wraps 'zathura --mode presentation'; zathura --mode presentation $argv; end
function zd; zathura ~/Downloads/(ls ~/Downloads -t | head -n 1) $argv; end

# Show all errors (don't silently continue)
$ErrorActionPreference = "Continue"
$ErrorView = "DetailedView"

# Nix
if (Test-Path /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh) {
    $env:PATH = "/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:$env:PATH"
    $env:NIX_PROFILES = "/nix/var/nix/profiles/default /root/.nix-profile"
    $env:NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt"
}

# Cargo
if (Test-Path ~/.cargo/bin) {
    $env:PATH = "$HOME/.cargo/bin:$env:PATH"
}

# sr - source/reload profile
function sr {
    . $PROFILE
}

function sl {
    ls -A
}

# direnv aliases
function dira { git add -A; direnv allow }
function de { direnv allow; & $args[0] $args[1..$args.Length]; direnv deny }
function dirr { Remove-Item -Recurse -Force .direnv -ErrorAction SilentlyContinue; dira }
function dird { direnv deny }

# Prompt matching bash: path in blue, exit_code$ in green (0) or red (non-0)
function prompt {
    # MUST capture $? first before any other command resets it
    $success = $?
    $code = if ($success) { 0 } else { 1 }
    # Also check $LASTEXITCODE for external commands
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        $code = $LASTEXITCODE
    }

    $path = (Get-Location).Path -replace [regex]::Escape($HOME), "~"

    # Blue path
    Write-Host "$path " -ForegroundColor Blue -NoNewline

    # Exit code and $ in green or red
    if ($code -eq 0) {
        Write-Host "${code}`$ " -ForegroundColor Green -NoNewline
    } else {
        Write-Host "${code}`$ " -ForegroundColor Red -NoNewline
    }

    return ""
}

# direnv version check (2.37+ required for proper pwsh support)
$direnvVersion = direnv --version 2>$null
if ($direnvVersion) {
    $parts = $direnvVersion.Split('.')
    $major = [int]$parts[0]
    $minor = [int]$parts[1]
    if ($major -lt 2 -or ($major -eq 2 -and $minor -lt 37)) {
        Write-Host "WARNING: direnv $direnvVersion is outdated. Version 2.37+ required for PowerShell support." -ForegroundColor Yellow
        Write-Host "Update: curl -L -o /tmp/direnv https://github.com/direnv/direnv/releases/latest/download/direnv.linux-amd64 && chmod +x /tmp/direnv && sudo mv /tmp/direnv /usr/bin/direnv" -ForegroundColor Yellow
    }
}

# direnv hook
Invoke-Expression "$(direnv hook pwsh)"

# Editor aliases (evil-helix)
Set-Alias -Name nvim -Value hx
Set-Alias -Name vim -Value hx
Set-Alias -Name vi -Value hx

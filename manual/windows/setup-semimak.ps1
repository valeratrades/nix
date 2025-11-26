#!/usr/bin/env pwsh
# Semimak Setup Script for Windows
# Downloads and configures Kanata with Semimak layout
#
# Usage (from PowerShell with admin rights):
#   irm https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/master/manual/windows/setup-semimak.ps1 | iex
# Or download and run:
#   Invoke-WebRequest -Uri "https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/master/manual/windows/setup-semimak.ps1" -OutFile "setup-semimak.ps1"
#   .\setup-semimak.ps1

$ErrorActionPreference = "Stop"

Write-Host "=== Semimak Setup for Windows ===" -ForegroundColor Cyan
Write-Host ""

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "WARNING: Not running as administrator. Kanata may require admin rights." -ForegroundColor Yellow
    Write-Host "Consider right-clicking PowerShell and selecting 'Run as Administrator'" -ForegroundColor Yellow
    Write-Host ""
    $continue = Read-Host "Continue anyway? (y/N)"
    if ($continue -ne "y") {
        exit 1
    }
}

# Create config directory
$configDir = "$env:USERPROFILE\.config\kanata"
Write-Host "[1/4] Creating config directory: $configDir" -ForegroundColor Green
New-Item -ItemType Directory -Force -Path $configDir | Out-Null

# Install Kanata
Write-Host "[2/4] Installing Kanata..." -ForegroundColor Green
try {
    winget install --id=jtroo.kanata_gui -e --accept-package-agreements --accept-source-agreements
    Write-Host "✓ Kanata installed successfully" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to install Kanata: $_" -ForegroundColor Red
    Write-Host "You may need to install winget first or install Kanata manually from:" -ForegroundColor Yellow
    Write-Host "https://github.com/jtroo/kanata/releases" -ForegroundColor Yellow
    exit 1
}

# Download Semimak config
Write-Host "[3/4] Downloading Semimak configuration..." -ForegroundColor Green
$configUrl = "https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/master/manual/windows/semimak.kbd"
$configPath = "$configDir\semimak.kbd"

# TODO: Update this URL with your actual repository
# For now, create the config inline
$semimakConfig = @'
;; Semimak Layout for Kanata
;; Based on /home/xkb_symbols/semimak
;; For French AZERTY keyboard

(defcfg
  process-unmapped-keys yes
)

;; French AZERTY physical layout
;; Note: defsrc uses the scan codes, which are the same regardless of OS layout
;; But we need to account for where keys physically are on an AZERTY keyboard
(defsrc
  grv  1    2    3    4    5    6    7    8    9    0    -    =    bspc
  tab  q    w    e    r    t    y    u    i    o    p    [    ]    \
  caps a    s    d    f    g    h    j    k    l    ;    '    ret
  lsft z    x    c    v    b    n    m    ,    .    /    rsft
  lctl lmet lalt           spc            ralt rmet rctl
)

(deflayer semimak
  grv  1    2    3    4    5    6    7    8    9    0    [    ]    bspc
  tab  f    l    h    v    z    q    w    u    o    y    /    =    \
  caps s    r    n    t    k    c    d    e    a    i    -    ret
  lsft x    '    b    m    j    p    g    ,    .    ;    rsft
  lctl lmet lalt           spc            bspc rmet rctl
)

;; Key mapping explanation:
;; Top row (AD):    f l h v z  q w u o y
;; Home row (AC):   s r n t k  c d e a i
;; Bottom row (AB): x ' b m j  p g , . ;
;;
;; Symbol placement from XKB config:
;; AE11: [ {    (was - _)
;; AE12: ] }    (was = +)
;; AD11: / ?    (was [ {)
;; AD12: = +    (was ] })
;; AC11: - _    (was ; :)
;; AB10: ; :    (was / ?)
;;
;; Special mappings:
;; Right Alt -> Backspace (ralt in semimak layer)
'@

$semimakConfig | Out-File -FilePath $configPath -Encoding UTF8
Write-Host "✓ Semimak config created at: $configPath" -ForegroundColor Green

# Create startup script
Write-Host "[4/4] Creating startup shortcut..." -ForegroundColor Green
$startupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$startupScript = "$configDir\start-kanata.ps1"
$startupScriptContent = @"
# Start Kanata with Semimak layout
Start-Process -FilePath "kanata" -ArgumentList "--cfg `"$configPath`"" -WindowStyle Hidden
"@

$startupScriptContent | Out-File -FilePath $startupScript -Encoding UTF8

# Create VBS wrapper to run PowerShell script invisibly
$vbsWrapper = "$startupDir\Kanata-Semimak.vbs"
$vbsContent = @"
Set objShell = CreateObject("WScript.Shell")
objShell.Run "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$startupScript`"", 0, False
"@

$vbsContent | Out-File -FilePath $vbsWrapper -Encoding ASCII
Write-Host "✓ Startup shortcut created" -ForegroundColor Green

Write-Host ""
Write-Host "=== Setup Complete! ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Restart your computer (or start Kanata manually)" -ForegroundColor White
Write-Host "2. Kanata will start automatically on login" -ForegroundColor White
Write-Host ""
Write-Host "To start Kanata now, run:" -ForegroundColor Yellow
Write-Host "  kanata --cfg `"$configPath`"" -ForegroundColor White
Write-Host ""
Write-Host "Config file location: $configPath" -ForegroundColor Cyan
Write-Host "Startup script location: $vbsWrapper" -ForegroundColor Cyan
Write-Host ""
Write-Host "Note: Kanata may require admin privileges to intercept keystrokes." -ForegroundColor Yellow
Write-Host "If it doesn't work, try running Kanata as administrator." -ForegroundColor Yellow

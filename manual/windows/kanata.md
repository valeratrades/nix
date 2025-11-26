# Semimak Setup for Windows

## Automated Setup (Recommended)

Run this in PowerShell as Administrator:

```pwsh
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/master/manual/windows/setup-semimak.ps1" -UseBasicParsing | Invoke-Expression
```

Or download first:

```pwsh
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/master/manual/windows/setup-semimak.ps1" -OutFile "setup-semimak.ps1"
.\setup-semimak.ps1
```

## Manual Setup

If you prefer to install manually:

```pwsh
# 1. Install Kanata
winget install --id=jtroo.kanata_gui -e

# 2. Download the Semimak config
$configDir = "$env:USERPROFILE\.config\kanata"
New-Item -ItemType Directory -Force -Path $configDir
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/master/manual/windows/semimak.kbd" -OutFile "$configDir\semimak.kbd"

# 3. Start Kanata with Semimak layout
kanata --cfg "$configDir\semimak.kbd"
```

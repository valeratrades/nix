# Semimak Setup for Windows

## Automated Setup (Recommended)

Run this in Command Prompt (cmd.exe) as Administrator:

```cmd
curl -o setup-semimak.ps1 https://raw.githubusercontent.com/valeratrades/nix/master/manual/windows/setup-semimak.ps1
powershell -ExecutionPolicy Bypass -File setup-semimak.ps1
```

## Manual Setup

If you prefer to install manually, run in Command Prompt as Administrator:

```cmd
winget install --id=jtroo.kanata_gui -e
mkdir "%USERPROFILE%\.config\kanata"
curl -o "%USERPROFILE%\.config\kanata\semimak.kbd" https://raw.githubusercontent.com/valeratrades/nix/master/manual/windows/semimak.kbd
kanata --cfg "%USERPROFILE%\.config\kanata\semimak.kbd"
```

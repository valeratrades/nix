# metascalp

Binance→MEXC delta arbitrage bot from metascalp.io. Watches Binance futures price via WebSocket; when the spread vs MEXC exceeds a configurable tick threshold, it opens a position on MEXC and closes it when the spread narrows (or on TP/SL/timeout).

## Running

```
~/metascalp/run
```

On first launch after setup (or if the MEXC session expires): Chrome opens to MEXC futures, log in manually, press Enter in the terminal. Session is saved to `~/metascalp/mexc_session/` — subsequent runs skip the browser entirely.

## Files

```
~/metascalp/
  run                  # launcher (nix-shell wrapper)
  shell.nix            # nix-shell dependency spec
  main.pyc             # app entry point (Python 3.12 bytecode)
  core/__pycache__/    # app modules (contract_info, logger, mexc_http_order, state, ui, wss)
  data/config.ini      # trading config (see below)
  logs/                # daily trade logs (YYYY-MM-DD.log)
  mexc_session/        # Chromium user data dir — MEXC login session
```

## Config (`data/config.ini`)

```ini
[MEXC]
Access_Key = ...
Secret_Key = ...

[Настройки торгов]
Включить_торги = Да          # Да/Нет
Включить_логи = Да
Монета = TAOUSDT
Объём_позиции = 10$
Плечо = 10

Delta_для_входа_в_тиках = 12    # open when spread >= N ticks
Delta_для_выхода_в_тиках = 5    # close when spread narrows to N ticks

Take_Profit_в_тиках = 15
Stop_Loss_в_тиках = 20
Timeout_секунд = 90
Пауза_после_сделки_секунд = 3

; limit / market
Способ_открытия_позиции = market
Способ_закрытия_позиции = market
```

1 tick = `price_unit` (fetched from MEXC contract info at startup). For TAO_USDT: `priceScale=2`, so 1 tick = 0.01.

## How it works internally

The app is a PyInstaller-bundled Python 3.12 executable (Windows). It was unwrapped and runs natively on Linux.

**Startup sequence:**
1. Reads `data/config.ini`
2. Fetches contract metadata from MEXC API (tick size, contract size, min vol)
3. Launches Chrome once via Playwright to extract `uc_token` + fingerprint from the MEXC web app's webpack state — then closes the browser
4. All subsequent order traffic goes through `aiohttp` directly (~30–50 ms latency)

**Hot path:**
- `binance_ws` — subscribes to `@aggTrade` on Binance futures WS, updates `state.price_binance`
- `mexc_ws` — subscribes to deal feed on MEXC contract WS, updates `state.price_mexc`
- `check_trade_logic` (called on every MEXC tick) — compares prices, fires `_do_open` / `_do_close`

**Order sides:** 1=LONG open, 2=LONG close, 3=SHORT open, 4=SHORT close.

## NixOS setup

The Windows session cookies are DPAPI-encrypted and cannot be migrated to Linux — a one-time re-login is required.

Playwright's `channel='chrome'` hardcodes `/opt/google/chrome/chrome` on Linux. A persistent symlink is created via `systemd.tmpfiles.rules` in `os/nixos/configuration.nix`:

```nix
systemd.tmpfiles.rules = [
  ...
  "d /opt/google/chrome 0755 root root -"
  "L /opt/google/chrome/chrome - - - - ${pkgs.google-chrome}/bin/google-chrome-stable"
];
```

Python deps served via `nix-shell`: `python312`, `aiohttp`, `orjson`, `colorama`, `playwright`, `websockets`.

## Re-setup from scratch

If `~/metascalp/` is lost, the source is the `.exe` in `~/Downloads/Telegram Desktop/`. Steps:

```bash
# 1. Get pyinstxtractor
curl -sL https://raw.githubusercontent.com/extremecoders-re/pyinstxtractor/master/pyinstxtractor.py -o /tmp/pyinstxtractor.py

# 2. Extract PyInstaller bundle (must use Python 3.12 — matches the bundle's version)
cd /tmp
nix-shell -p python312 --run "python3 /tmp/pyinstxtractor.py '/path/to/Launcher v1.1a.exe'"

# 3. Recreate directory structure
mkdir -p ~/metascalp/core/__pycache__ ~/metascalp/{data,logs,mexc_session}
cp /tmp/"Launcher v1.1a.exe_extracted"/main.pyc ~/metascalp/
for f in /tmp/"Launcher v1.1a.exe_extracted"/PYZ.pyz_extracted/core/*.pyc; do
  base=$(basename "$f" .pyc)
  cp "$f" ~/metascalp/core/__pycache__/${base}.cpython-312.pyc
done
touch ~/metascalp/core/__init__.py

# 4. Restore config and session
cp data/config.ini ~/metascalp/data/
cp -r mexc_session/. ~/metascalp/mexc_session/
```

Recreate `~/metascalp/run` (chmod +x after):

```bash
#!/usr/bin/env bash
set -e
cd "$(dirname "$(readlink -f "$0")")"

exec nix-shell \
  -p python312 \
  -p python312Packages.aiohttp \
  -p python312Packages.orjson \
  -p python312Packages.colorama \
  -p python312Packages.playwright \
  -p python312Packages.websockets \
  --run "python3 main.pyc"
```

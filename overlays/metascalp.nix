# metascalp Binance→MEXC delta arbitrage bot (native Python, extracted from Windows PyInstaller bundle)
# Bytecode + mutable state (config, logs, session) live in ~/metascalp/
final: prev:
{
  metascalp = prev.writeShellApplication {
    name = "metascalp";
    runtimeInputs = [
      (prev.python312.withPackages (ps: with ps; [
        aiohttp
        orjson
        colorama
        playwright
        websockets
      ]))
    ];
    text = ''
      cd ~/metascalp
      exec python3 main.pyc
    '';
  };
}

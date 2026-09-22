{ ... }:
{
  # Google Chrome managed policy: force Memory Saver on and keep only the tabs we actually care about live; everything else is free to be discarded so it stops burning CPU/RAM in the background (47 renderers / ~12GB otherwise).
  environment.etc."opt/chrome/policies/managed/memory-saver.json".text = builtins.toJSON {
    HighEfficiencyModeEnabled = true;
    MemorySaverModeSavings = 2; # 0=Moderate, 1=Balanced, 2=Maximum (Chrome 126+)
    # Bare host = that domain + all subdomains (futures.*, app.*, accounts.*).
    # Trading venues: notifications are critical, so keep every venue we might
    # be active on alive. Extra unused entries cost nothing.
    TabDiscardingExceptions = [
      "calendar.google.com"
      "aggr.trade"
      "valeratrades.com"
      "evinvest.org"
      # Major CEXes
      "binance.com"
      "bybit.com"
      "okx.com"
      "mexc.com"
      "bitget.com"
      "gate.io"
      "gate.com"
      "kucoin.com"
      "htx.com"        # ex-Huobi
      "kraken.com"
      "coinbase.com"
      "bingx.com"
      "bitunix.com"
      "bitmart.com"
      "lbank.com"
      "coinex.com"
      "bitfinex.com"
      "bitstamp.net"
      "crypto.com"
      "whitebit.com"
      "phemex.com"
      "deribit.com"
      "bitmex.com"
      "weex.com"
      "blofin.com"
      "toobit.com"
      "xt.com"
      "probit.com"
      "ascendex.com"
      # DEX / perps
      "hyperliquid.xyz"
      "dydx.exchange"
      "dydx.trade"
      "gmx.io"
      "drift.trade"
      "vertexprotocol.com"
      "apex.exchange"
      "paradex.trade"
      "aevo.xyz"
      "jup.ag"         # Jupiter (Solana)
      "app.uniswap.org"
      "uniswap.org"
    ];
  };

  environment.etc."opt/chrome/policies/managed/protocols.json".text = builtins.toJSON {
    AutoLaunchProtocolsFromOrigins = [
      { protocol = "gologin"; allowed_origins = [ "https://app.gologin.com" ]; } # desktop login handoff
    ];
  };

  # Machine-wide, so every profile gets the same set regardless of account.
  environment.etc."opt/chrome/policies/managed/extensions.json".text = builtins.toJSON {
    ExtensionInstallForcelist = map (id: "${id};https://clients2.google.com/service/update2/crx") [
      "abocjojdmemdpiffeadpdnicnlhcndcg" # SocialFocus
      "ajlhmclpjddfebgfpahnlodliljdnbie" # Moss
      "bolmmhkapeekgcjopdmnbmnhgaapbpdb" # FocusTube
      "ccnnhhnmpoffieppjjkhdakcoejcpbga" # Rearrange Tabs
      "ckagfhpboagdopichicnebandlofghbc" # Shorts Blocker
      "dbepggeogbaibhgnhhndojpepiihcmeb" # Vimium
      "ddkjiahejlhfcafbddmgiahcphecmpfh" # uBlock Origin Lite
      "dhdgffkkebhmkfjojejmpbldmpobfkfo" # Tampermonkey
      "dodmmooeoklaejobgleioelladacbeki" # Ona
      "egjidjbpglichdcondbcbdnbeeppgdph" # Trust Wallet
      "eimadpbcbfnmbkopoojfekhnkhdbieeh" # Dark Reader
      "enboaomnljigfhfjfoalacienlhjlfil" # UnTrap for YouTube
      "ghbdjeckopemkoomopmpgjifafpcjhga" # TabPilot
      "gppongmhjkpfnbhagpmjfkannfbllamg" # Wappalyzer
      "hijfnlgdhfpmnckieikhinolopcolofe" # GMBspy
      "hmbdemoadbcdfmdjiokhcnoaoepgbhbn" # Block Notifications
      "jgibaoklabopileepldnlkbbcibhbgmd" # Youtube Transcript
      "jnbbnacmeggbgdjgaoojpmhdlkkpblgi" # WakaTime
      "jplgfhpmjnbigmhklmmbgecoobifkmpa" # Proton VPN
      "kfhkeghcignojkdcnemgcggojlmneema" # LockedIn AI
      "kogfodpcilmconphbpldnipakepicaia" # Better Muted Words
      "linlakoepnjkdiphemdpbphnjlppjedm" # X Mute
      "mnjggcdmjocbbbhaepdhchncahnbgone" # SponsorBlock
      "nhocmlminaplaendbabmoemehbpgdemn" # Fathom AI Note Taker
      "nkbihfbeogaeaoehlefnkodbefgpgknn" # MetaMask
      "ofpnikijgfhlmmjlpkfaifhhdonchhoi" # Accept all cookies
      "ogcgkffhplmphkaahpmffcafajaocjbd" # ZenHub
      "omghfjlpggmjjaagoclmmobgdodcjboh" # Browsec VPN
      "pbanhockgagggenencehbnadejlgchfc" # Simplify Copilot
      "pmjeegjhjdlccodhacdgbgfagbpmccpe" # Clockify
    ];
  };
}

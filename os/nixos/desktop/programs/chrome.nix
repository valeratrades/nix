{ config, lib, pkgs, user, ... }:
let
  tabDiscardingExceptions = [
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

  # Discards every inactive tab at browser startup, so restored tabs load only when visited.
  # Chrome installs a new build only when the manifest version goes up.
  # Packed at login rather than in the store: the signing key (which fixes the ID) lives in sops.
  lazyRestoreId = "ekfifhbofidfehoabdglklkgdghjimja";
  lazyRestoreDir = "${config.users.users.${user.username}.home}/.local/share/chrome-lazy-restore";
  lazyRestore = config.home-manager.users.${user.username}.sops.secrets ? chrome_lazy_restore_pem;
  lazyRestoreSrc = pkgs.runCommand "chrome-lazy-restore-src" { } ''
    cp -r ${../../../../home/config/chrome/lazy_restore} $out
    chmod -R u+w $out
    substituteInPlace $out/background.js --replace-fail 'const EXEMPT = [];' 'const EXEMPT = ${builtins.toJSON tabDiscardingExceptions};'
  '';
in
{
  # Google Chrome managed policy: force Memory Saver on and keep only the tabs we actually care about live; everything else is free to be discarded so it stops burning CPU/RAM in the background (47 renderers / ~12GB otherwise).
  environment.etc."opt/chrome/policies/managed/memory-saver.json".text = builtins.toJSON {
    HighEfficiencyModeEnabled = true;
    MemorySaverModeSavings = 2; # 0=Moderate, 1=Balanced, 2=Maximum (Chrome 126+)
    # Bare host = that domain + all subdomains (futures.*, app.*, accounts.*).
    # Trading venues: notifications are critical, so keep every venue we might
    # be active on alive. Extra unused entries cost nothing.
    TabDiscardingExceptions = tabDiscardingExceptions;
  };

  environment.etc."opt/chrome/policies/managed/protocols.json".text = builtins.toJSON {
    AutoLaunchProtocolsFromOrigins = [
      { protocol = "gologin"; allowed_origins = [ "https://app.gologin.com" ]; } # desktop login handoff
    ];
  };

  # Machine-wide, so every profile gets the same set regardless of account.
  environment.etc."opt/chrome/policies/managed/extensions.json".text = builtins.toJSON {
    ExtensionInstallForcelist = lib.optional lazyRestore "${lazyRestoreId};file://${lazyRestoreDir}/updates.xml" ++ map (id: "${id};https://clients2.google.com/service/update2/crx") [
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

  home-manager.users.${user.username} = { config, ... }: lib.mkIf lazyRestore {
    systemd.user.services.chrome-lazy-restore = {
      Unit = {
        Description = "Pack the lazy-restore Chrome extension with its sops-held key";
        After = [ "sops-nix.service" ];
        Requires = [ "sops-nix.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = toString (pkgs.writeShellScript "chrome-lazy-restore-pack" ''
          set -euo pipefail
          export PATH=${lib.makeBinPath [ pkgs.go-crx3 pkgs.jq pkgs.coreutils ]}
          mkdir -p ${lazyRestoreDir}
          crx3 pack ${lazyRestoreSrc} -p ${config.sops.secrets.chrome_lazy_restore_pem.path} -o ${lazyRestoreDir}/lazy_restore.crx
          id=$(crx3 id ${lazyRestoreDir}/lazy_restore.crx)
          [ "$id" = ${lazyRestoreId} ] || { echo "packed ID $id, policy expects ${lazyRestoreId}: key changed?" >&2; exit 1; }
          cat > ${lazyRestoreDir}/updates.xml <<EOF
          <?xml version='1.0' encoding='UTF-8'?>
          <gupdate xmlns='http://www.google.com/update2/response' protocol='2.0'>
            <app appid='${lazyRestoreId}'>
              <updatecheck codebase='file://${lazyRestoreDir}/lazy_restore.crx' version='$(jq -r .version ${lazyRestoreSrc}/manifest.json)' />
            </app>
          </gupdate>
          EOF
        '');
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}

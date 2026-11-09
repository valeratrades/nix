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

  # Packed at login rather than in the store: the signing key (which fixes the ID) lives in sops, as `other/chrome_<name>_pem`.
  # Chrome installs a new build only when the manifest version goes up.
  selfPacked = lib.filterAttrs (name: _: config.home-manager.users.${user.username}.sops.secrets ? "other/chrome_${name}_pem") {
    # Discards every inactive tab at browser startup, so restored tabs load only when visited.
    lazy_restore = {
      id = "ekfifhbofidfehoabdglklkgdghjimja";
      src = pkgs.runCommand "chrome-lazy-restore-src" { } ''
        cp -r ${../../../../home/config/chrome/lazy_restore} $out
        chmod -R u+w $out
        substituteInPlace $out/background.js --replace-fail 'const EXEMPT = [];' 'const EXEMPT = ${builtins.toJSON tabDiscardingExceptions};'
      '';
    };
    # Closing or leaving a page never asks "Leave site?".
    no_beforeunload = {
      id = "ncofhljbjmjbkmmjdbflhjfiblceilhc";
      src = ../../../../home/config/chrome/no_beforeunload;
    };
  };
  dashed = lib.replaceStrings [ "_" ] [ "-" ];
  packDir = name: "${config.users.users.${user.username}.home}/.local/share/chrome-${dashed name}";
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
    # Content scripts otherwise inject into every page; runtime_allowed_hosts beats runtime_blocked_hosts.
    ExtensionSettings = {
      "ajlhmclpjddfebgfpahnlodliljdnbie" = { # Moss: 5.4MB per page
        runtime_blocked_hosts = [ "*://*" ];
        runtime_allowed_hosts = [ "*://*.x.com" "*://*.twitter.com" ];
      };
      "pmjeegjhjdlccodhacdgbgfagbpmccpe".runtime_blocked_hosts = [ "*://*" ]; # Clockify: kept installed (and its data), inert
    };
    "3rdparty".extensions."oboonakemofpalcgghocfoadofidjkkk".settings.passkeys = true; # KeePassXC-Browser
    ExtensionInstallForcelist = lib.mapAttrsToList (name: e: "${e.id};file://${packDir name}/updates.xml") selfPacked ++ map (id: "${id};https://clients2.google.com/service/update2/crx") [
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
      "oboonakemofpalcgghocfoadofidjkkk" # KeePassXC-Browser
      "ofpnikijgfhlmmjlpkfaifhhdonchhoi" # Accept all cookies
      "ogcgkffhplmphkaahpmffcafajaocjbd" # ZenHub
      "omghfjlpggmjjaagoclmmobgdodcjboh" # Browsec VPN
      "pbanhockgagggenencehbnadejlgchfc" # Simplify Copilot
      "pmjeegjhjdlccodhacdgbgfagbpmccpe" # Clockify
    ];
  };

  # home-manager installs native hosts for chromium only, not proprietary Chrome
  environment.etc."opt/chrome/native-messaging-hosts/org.keepassxc.keepassxc_browser.json".text = builtins.toJSON {
    name = "org.keepassxc.keepassxc_browser";
    description = "KeePassXC integration with native messaging support";
    path = "${config.home-manager.users.${user.username}.programs.keepassxc.package}/bin/keepassxc-proxy";
    type = "stdio";
    allowed_origins = [ "chrome-extension://oboonakemofpalcgghocfoadofidjkkk/" ];
  };

  home-manager.users.${user.username} = { config, ... }: {
    # Google account passkey lives here, so login never needs a phone
    programs.keepassxc = {
      enable = true;
      settings.Browser = {
        Enabled = true;
        UpdateBinaryPath = false; # manifest is the /etc one above
      };
      settings.Security.LockDatabaseScreenLock = false; # the login unlock is from sops anyway; relocking only brings back the password prompt
    };

    systemd.user.services = lib.mapAttrs' (name: e: lib.nameValuePair "chrome-${dashed name}" {
      Unit = {
        Description = "Pack the ${name} Chrome extension with its sops-held key";
        After = [ "sops-nix.service" ];
        Requires = [ "sops-nix.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = toString (pkgs.writeShellScript "chrome-${dashed name}-pack" ''
          set -euo pipefail
          export PATH=${lib.makeBinPath [ pkgs.go-crx3 pkgs.jq pkgs.coreutils ]}
          mkdir -p ${packDir name}
          crx3 pack ${e.src} -p ${config.sops.secrets."other/chrome_${name}_pem".path} -o ${packDir name}/${name}.crx
          id=$(crx3 id ${packDir name}/${name}.crx)
          [ "$id" = ${e.id} ] || { echo "packed ID $id, policy expects ${e.id}: key changed?" >&2; exit 1; }
          cat > ${packDir name}/updates.xml <<EOF
          <?xml version='1.0' encoding='UTF-8'?>
          <gupdate xmlns='http://www.google.com/update2/response' protocol='2.0'>
            <app appid='${e.id}'>
              <updatecheck codebase='file://${packDir name}/${name}.crx' version='$(jq -r .version ${e.src}/manifest.json)' />
            </app>
          </gupdate>
          EOF
        '');
      };
      Install.WantedBy = [ "default.target" ];
    }) selfPacked;
  };
}

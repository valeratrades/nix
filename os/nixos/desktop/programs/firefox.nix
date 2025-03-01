{ pkgs, ... }: {
  environment.systemPackages = [
    pkgs.firefox
  ];
  programs.firefox = {
    enable = true;
    languagePacks = [ "en-US" "ru" "fr" ];
    policies = {
      # privacy
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      EnableTrackingProtection = {
        Value = true;
        Locked = true;
        Cryptomining = true;
        Fingerprinting = true;
      };

      # simplicity
      DisplayMenuBar = "default-off"; # alternatives: "always", "never" or "default-on"
      DisableFirefoxAccounts = true;
      DisableAccounts = true;
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
      DontCheckDefaultBrowser = true;

      ExtensionSettings =
        let
          extension = shortId: uuid: {
            name = uuid;
            value = {
              install_url = "https://addons.mozilla.org/en-US/firefox/downloads/latest/${shortId}/latest.xpi";
              installation_mode = "normal_installed";
            };
          };
          # To add additional extensions, find it on addons.mozilla.org, find
          # the short ID in the url (like https://addons.mozilla.org/en-US/firefox/addon/!SHORT_ID!/)
          # Then, download the XPI by filling it in to the install_url template, unzip it,
          # run `jq .browser_specific_settings.gecko.id manifest.json` or
          # `jq .applications.gecko.id manifest.json` to get the UUID
          # 
          # Or potentially even simpler way of finding it: navigate to `about:support`, search for `Add-ons` section, and ids of all installed addons will be listed there.
        in
        builtins.listToAttrs ([
          {
            name = "*";
            value = {
              installation_mode = "blocked"; # will also uninstall extensions I remove from here, so this is always the sole source of truth.
            };
          }
        ]
        ++ [
          (extension "ublock-origin" "uBlock0@raymondhill.net") # best adblocker today (2025/02/28)
          (extension "darkreader" "addon@darkreader.org")
          (extension "tree-style-tab" "treestyletab@piro.sakura.ne.jp")
          (extension "vimium-ff" "{d7742d87-e61d-4b78-b8a1-b469842139fa}")
          (extension "browsec" "browsec@browsec.com")
          (extension "wappalyzer" "wappalyzer@crunchlabz.com")
          (extension "socialfocus" "{26b4f076-089c-4c69-8497-44b7e5c9faef}")
          (extension "ether-metamask" "webextension@metamask.io")
          (extension "tampermonkey" "firefox@tampermonkey.net")
          (extension "sponsorblock" "	sponsorBlocker@ajay.app")
          (extension "istilldontcareaboutcookies" "idcac-pub@guus.ninja")
          (extension "wakatime" "addons@wakatime.com")
          (extension "tab-rearranger" "{5968a446-b126-4279-8827-6889a180e3fa}")
        ]);
      #XXX: none of these work.
      "3rdparty".Extensions = {
        # source code is here: moz-extension://d3121fd9-eb69-4ae5-813d-45edf7cf74a8/pages/options.js
        "d3121fd9-eb69-4ae5-813d-45edf7cf74a8" = {
          searchEngines = "Like this?";
        };
        "{d7742d87-e61d-4b78-b8a1-b469842139fa}" = {
          keyMappings = "map j scrollDown\nmap k scrollUp"; #dbg
          smoothScroll = false;
          nextPatterns = "";
          previousPatterns = "";
          ignoreKeyboardLayout = true;
          searchEngines = "TODO";
        };
        "uBlock0@raymondhill.net" = {
          whiteList = [
            "chrome-extension-scheme"
            "moz-extension-scheme"
            "valeratrades"
          ];
        };
      };
    };

    preferences = {
      "browser.newtabpage.activity-stream.showSponsored" = false;
      "browser.newtabpage.activity-stream.system.showSponsored" = false;
      "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
    };
  };
}

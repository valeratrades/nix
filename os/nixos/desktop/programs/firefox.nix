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
        in
        "*".installation_mode = "blocked"; # blocks all addons except the ones specified below
      builtins.listToAttrs [
      (extension "ublock-origin" "uBlock0@raymondhill.net") # best adblocker today (2025/02/28)
      (extension "dark-reader" "addon@darkreader.org")
      (extension "tree-style-tab" "treestyletab@piro.sakura.ne.jp")
      ];
      };

      preferences = {
        "browser.newtabpage.activity-stream.showSponsored" = false;
        "browser.newtabpage.activity-stream.system.showSponsored" = false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
      };
    };
  }

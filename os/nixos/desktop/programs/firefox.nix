{ pkgs, ... }: {
  environment.systemPackages = [ pkgs.firefox ];
  programs.firefox = {
    enable = true;
    languagePacks = [ "en-US" "ru" "fr" "de" ];
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
      DisplayMenuBar =
        "default-off"; # alternatives: "always", "never" or "default-on"
      DisableFirefoxAccounts = true;
      DisableAccounts = true;
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
      DontCheckDefaultBrowser = true;
      DisableLoudnessNormalization = true;

      WebsiteFilter.Block = let
        block = domain: [ "*://${domain}/*" "*://*.${domain}/*" ];
      in builtins.concatLists [
          # hide to not even look at these {{{always
          #(block "youtube.com") #Q: difficult to block fully. Could there maybe be some consistent sub-parts of the link that I could block based on instead?
          (block "tankionline.com")
          (block "instagram.com")
          (block "wcoflix.tv")
          (block "wcostream.tv")
          (block "ridomovies.tv")
          (block "moviesjoy.cx")
          (block "anigo.to")
          (block "imdb.com")
          (block "chat*")
          (block "anime*")
          #,}}}1
      ];

      ExtensionSettings = let
        extension = shortId: uuid: {
          name = uuid;
          value = {
            install_url =
              "https://addons.mozilla.org/en-US/firefox/downloads/latest/${shortId}/latest.xpi";
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
      in builtins.listToAttrs ([{
        name = "*";
        value = {
          installation_mode =
            #"blocked"; # will also uninstall extensions I remove from here, so this is always the sole source of truth. // To temporarily disable, switch to "normal_installed"
            "normal_installed"; #dbg
        };
      }] ++ [
				#NB: for extensions with just a hash, put it inside curly brackets
        (extension "ublock-origin"
          "uBlock0@raymondhill.net") # best adblocker today (2025/02/28)
        (extension "darkreader" "addon@darkreader.org")
        (extension "tree-style-tab" "treestyletab@piro.sakura.ne.jp")
        (extension "vimium-ff" "{d7742d87-e61d-4b78-b8a1-b469842139fa}")
        (extension "browsec" "browsec@browsec.com")
        (extension "wappalyzer" "wappalyzer@crunchlabz.com")
        (extension "socialfocus" "{26b4f076-089c-4c69-8497-44b7e5c9faef}")
        (extension "ether-metamask" "webextension@metamask.io")
        (extension "tampermonkey" "firefox@tampermonkey.net")
        #(extension "sponsorblock" "sponsorBlocker@ajay.app")
        (extension "sponsorblock" "{76383ca8-fe81-4645-b91f-d28e319619ad}")
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
        #XXX: doesn't seem to do it
        "{d7742d87-e61d-4b78-b8a1-b469842139fa}" = {
          keyMappings = ''
            map j scrollDown
            map k scrollUp''; # dbg
          smoothScroll = false;
          nextPatterns = "";
          previousPatterns = "";
          ignoreKeyboardLayout = true;
          searchEngines = "TODO";
        };
        "uBlock0@raymondhill.net" = {
          whiteList =
            [ "chrome-extension-scheme" "moz-extension-scheme" "valeratrades" ];
        };
      };
    };

    preferences = {
      # Disable GPU-accelerated rendering to prevent amdgpu hangs
      "gfx.webrender.all" = false;
      "browser.newtabpage.activity-stream.showSponsored" = false;
      "browser.newtabpage.activity-stream.system.showSponsored" = false;
      "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
      "widget.use-xdg-desktop-portal.file-picker" =
        1; # TODO: get it to use nvim for file picking
      "media.default_volume" =
        "0.3"; # stupid firefox does some cursed shit with resetting loudness to value here once in a while
      "media.scale_volume" = "0.5";
      # Don't share location {{{
      "geo.enabled" = false;
      "network.dns.disablePrefetch" =
        true; # prevent DNS-based location inference
      "media.peerconnection.enabled" = false; # prevent IP leaks
      #,}}}
    };
  };
}

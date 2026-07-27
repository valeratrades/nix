{ ...
}:
let
  vencord_plugins = {
    alwaysTrust = {
      enable = true;
      file = true;
    };
    copyFileContents.enable = true;
    #betterSettings.enable = true;
    biggerStreamPreview.enable = true;
    copyUserUrLs.enable = true;
    #dearrow.enable = true; # less sensational yt thumbnails
    #experiments = {
    #  toolbarDevMenu = true;
    #  enable = true;
    #};
    #fakeNitro = {
    #  enable = true;
    #  emojiSize = 14; # default 48
    #  disableEmbedPermissionCheck = true;
    #};
    favoriteEmojiFirst.enable = true; # prefer favorit in emoji autocomplete
    ctrlEnterSend = {
      submitRule = "enter"; # while <C-<CR>> is indeed better in vacuum, it's non-standard.
      sendMessageInTheMiddleOfACodeBlock = true;
    };
    fixCodeblockGap.enable = true; # trims trailing newline after codeblocks
    friendInvites.enable = true; # `/create` command suite
    friendsSince.enable = true;
    ignoreActivities = {
      enable = true;
      ignoreListening = true;
      ignoreCompeting = true;
    };
    #memberCount.enable = true;
    messageClickActions.enable = true; # double-click to edit/reply, backspace+click to delete
    noOnboardingDelay.enable = true; # claims to cut load times
    noUnblockToJump.enable = true;
    #pinDMs = {
    #  enable = true;
    #  pinOrder = "custom";
    #};
    reactErrorDecoder.enable = true; # don't minimize react errors
    showHiddenThings = {
      # bunch of moderator-only things I'm not supposed to see
      enable = true;
    };
    #unsuppressEmbeds.enable = true;
    viewRaw.enable = true; # left-click
    #youtubeAdblock.enable = true; # for yt embeds
  };
in
{
  programs.nixcord = {
    enable = true; # also installs discord package
    discord.enable = true; # when Vesktop is available, it's strictly preferable
    vesktop.enable = true;
    discord.openASAR.enable = true;

    # NB: nixcord *copies* this over ~/.config/discord/settings.json on every activation rather than
    # symlinking, so this attrset is the whole file — anything left out is silently dropped. The
    # transient keys Discord writes itself (WINDOW_BOUNDS, IS_MAXIMIZED, trayBalloonShown) are
    # deliberately absent and will simply be re-created at runtime.
    discord.settings = {
      # Closing the window quits, rather than parking Discord in the tray. Left to its own devices it
      # sat "closed" in the tray burning ~32% of a core for ten hours straight.
      MINIMIZE_TO_TRAY = false;
      OPEN_ON_STARTUP = false;
      START_MINIMIZED = false;

      SKIP_HOST_UPDATE = true; # nix owns the package; never let it self-update
      openasar.setup = true; # matches discord.openASAR.enable above
      DANGEROUS_ENABLE_DEVTOOLS_ONLY_ENABLE_IF_YOU_KNOW_WHAT_YOURE_DOING = true;
      BACKGROUND_COLOR = "#2c2d32";
      enableHardwareAcceleration = true;
      offloadAdmControls = true;
      asyncVideoInputDeviceInit = false;
      openH264Enabled = true;
      chromiumSwitches = { };
    };

    vesktopConfig = {
      frameless = true;
      enableReactDevtools = true;
      plugins = vencord_plugins;
    };
    extraConfig = {
      # Some extra JSON config here
      # ...
    };
  };
}

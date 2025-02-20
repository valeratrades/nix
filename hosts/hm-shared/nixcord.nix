{
  ...
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
    copyUserURLs.enable = true;
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
    fixCodeblockGap.enable = true;
    friendInvites.enable = true; # `/create` command suite
    friendsSince.enable = true;
    ignoreActivities = {
      enable = true;
      ignoreListening = true;
      ignoreCompeting = true;
    };
    #memberCount.enable = true;
    messageClickActions.enable = true; # double-click to edit/reply, backspace+click to delete
    noOnboardingDelay.enable = true;
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
    discord.enable = true;
    vesktop.enable = true;
    discord.openASAR.enable = true;

    config = {
      frameless = true;
      enableReactDevtools = true;
      plugins = vencord_plugins;
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

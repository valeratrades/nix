{
  ...
}:
{
  programs.nixcord = {
    enable = true; # also installs discord package
    discord.enable = true;
    vesktop.enable = true;
    discord.openASAR.enable = true;

    #TODO: move this and I guess whole nixcord setup out into its own mod
    quickCss = ''
      [class^=message] [id^=message-content] :is(h1, h2, h3, li) {
        margin: 0px;
      }
      /* Hide GIF button */
      .buttonContainer-2lnNiN:not(.apateE2EButton):not(.send-button)> :not(.emojiButton-3FRTuj):not(.fm-button)> :not(.stickerButton-1-nFh2):not(.apateEncryptionKeyContainer):not(.translateButton-DhP9x8) {
          display: none;
      }

      /* Hide Stickers button */
      .stickerButton-1-nFh2 {
          display: none;
      }
      /* Compact Blocked Messages */
      .scrollerInner-2PPAp2>.groupStart-3Mlgv1:not(.backgroundFlash-1X5jVs)>.wrapper-30-Nkg {
          padding: 0 0 0 16px
      }

      .scrollerInner-2PPAp2>.groupStart-3Mlgv1:not(.backgroundFlash-1X5jVs)>.wrapper-30-Nkg.compact-2Nkcau {
          padding: 0 0 0 108px
      }

      .scrollerInner-2PPAp2>.groupStart-3Mlgv1:not(.backgroundFlash-1X5jVs) {
          margin: 0
      }

      .scrollerInner-2PPAp2>.groupStart-3Mlgv1.expanded-3lghlw:not(.backgroundFlash-1X5jVs) {
          background-color: var(--info-danger-background)
      }

      .scrollerInner-2PPAp2>.groupStart-3Mlgv1:not(.backgroundFlash-1X5jVs) .messageListItem-ZZ7v6g .groupStart-3Mlgv1,
      .scrollerInner-2PPAp2>.groupStart-3Mlgv1:not(.backgroundFlash-1X5jVs, .expanded-3lghlw)+.messageListItem-ZZ7v6g .groupStart-3Mlgv1 {
          margin-top: 0
      }

      .scrollerInner-2PPAp2>.groupStart-3Mlgv1:not(.backgroundFlash-1X5jVs) .messageListItem-ZZ7v6g {
          opacity: .5
      }

      .blockedSystemMessage-3FmE9n .iconContainer-2rPbqG {
          display: none
      }

      .blockedMessageText-3Zeg3y {
          position: relative;
          font-size: 12px;
          line-height: 16px;
          color: var(--interactive-muted)
      }

      .blockedMessageText-3Zeg3y:hover {
          text-decoration: underline
      }

      .blockedMessageText-3Zeg3y:hover,
      .groupStart-3Mlgv1.expanded-3lghlw .blockedMessageText-3Zeg3y {
          color: var(--info-danger-foreground)
      }

      .blockedAction-2cPk2G {
          position: absolute;
          inset: 0;
          width: 100%;
          opacity: 0
      }

      .blockedMessageText-3Zeg3y:after {
          content: \'\';
          position: absolute;
          right: 0;
          height: 100%;
          width: 14px;
          pointer-events: none;
          background-color: currentColor;
          -webkit-mask: url('data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 18 24" fill="currentColor"><path fill-rule="evenodd" clip-rule="evenodd" d="M15 3.999V2H9V3.999H3V5.999H21V3.999H15Z M5 6.99902V18.999C5 20.101 5.897 20.999 7 20.999H17C18.103 20.999 19 20.101 19 18.999V6.99902H5ZM11 17H9V11H11V17ZM15 17H13V11H15V17Z" ></path></svg>') center/contain no-repeat
      }

      .container-1NXEtd .content-2a4AW9>div[style="height: 16px;"]:nth-child(2) {
          display: none;
      }
    '';
    config = {
      useQuickCss = true;
      frameless = true;
      enableReactDevtools = true;
      plugins = {
        alwaysTrust = {
          enable = true;
          file = true;
        };
        copyFileContents.enable = true;
        betterSettings.enable = true;
        biggerStreamPreview.enable = true;
        copyUserURLs.enable = true;
        dearrow.enable = true; # less sensational yt thumbnails
        experiments = {
          toolbarDevMenu = true;
          enable = true;
        };
        fakeNitro = {
          enable = true;
          emojiSize = 14; # default 48
          disableEmbedPermissionCheck = true;
        };
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
        loadingQuotes = {
          enable = true;
          enableDiscordPresetQuotes = false;
          additionalQuotes = "...";
          additionalQuotesDelimiter = "|";
        };
        memberCount.enable = true;
        messageClickActions.enable = true; # double-click to edit/reply, backspace+click to delete
        noOnboardingDelay.enable = true;
        noUnblockToJump.enable = true;
        pinDMs = {
          enable = true;
          pinOrder = "custom";
        };
        reactErrorDecoder.enable = true; # don't minimize react errors
        showHiddenThings = {
          # bunch of moderator-only things I'm not supposed to see
          enable = true;
        };
        unsuppressEmbeds.enable = true;
        viewRaw.enable = true; # left-click
        youtubeAdblock.enable = true; # for yt embeds
      };
    };
    extraConfig = {
      # Some extra JSON config here
      # ...
    };
  };
}

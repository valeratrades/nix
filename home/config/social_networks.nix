{
  dms = {
    discord = {
      user_token = { env = "DISCORD_AUTH"; };
      my_username = { env = "DEFAULT_USERNAME"; };
    };
    monitored_users = [ "play_me_once" "deevsdeevs" ];
  };

  telegram = {
    bot_token = { env = "TELEGRAM_BOT_KEY"; };
    channel_alerts = { env = "TELEGRAM_ALERTS_CHANNEL_ID"; };
    channel_output = "WatchingTT";
    api_id = 19721916;
    api_hash = { env = "TELEGRAM_API_HASH"; };
    phone = { env = "PHONE_NUMBER_FR"; };
    username = "@valeratrades";
    poll_channels = [
      "https://t.me/cryptonarnianews"
      "https://t.me/marzherubs"
      "https://t.me/thedailyape"
      "https://t.me/alfablock"
      "https://t.me/elliottwaveschool"
      "https://t.me/Coin_Post"
      "https://t.me/TraderRBTA"
    ];
    info_channels = [
      "https://t.me/kopeechkav"
    ];
  };

  twitter = {
    # bearer_token from @valeratrades — does not have to match the posting account in oauth below
    bearer_token = { env = "TWITTER_MASTER_BEARER_TOKEN"; };
    sometimes_polls_list = "1507244316154023968";
    everytime_polls_list = "1507245210547409040";
    oauth = {
      acc_username = "valera_other";
      api_key = { env = "TWITTER_OTHER_API_PUBKEY"; };
      api_key_secret = { env = "TWITTER_OTHER_API_SECRET"; };
      access_token = { env = "TWITTER_OTHER_ACCESS_PUBKEY"; };
      access_token_secret = { env = "TWITTER_OTHER_ACCESS_SECRET"; };
    };
    poll = {
      duration_hours = 24;
      schedule_every = "1w";
      num_of_retries = 5;
      text = ''
Sentiment check: $BTC, how are we feeling?

for future reference: $BTC ~''${btc_price}
- [ ] Bullish
- [ ] Neutral
- [ ] Bearish
- [ ] show results
'';
    };
  };

  youtube = {
    channels = {
      hamaha = "UCI3uVtN-W5StRN1RsLNKV6g";
      test = "UCG5YX-fn1-EIv-sOSYMjSmg"; # Q: still relevant?
    };
  };

  email = {
    email = "valeratrades@gmail.com";
    ignore_patterns = [ "Alex Hormozi" "imperiumlabs" ];
    claude_token = { env = "CLAUDE_TOKEN"; };
    important_if_contains = {
      any = [];
      subject = [ "Appointment booked" ];
      body = [];
      address = [];
    };
    auth = {
      imap = {
        pass = { env = "GOOGLE_MAIN_MAIL_PASS"; };
      };
    };
  };
}

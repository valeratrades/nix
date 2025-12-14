{
  # Optional: Add balances not tracked on exchanges (in USD)
  # other_balances = 1000.0;
  exchanges = import ./shared/exchanges.nix;
  #exchanges = {
  #  binance = {
  #    api_pubkey.env = "BINANCE_TIGER_FULL_PUBKEY";
  #    api_secret.env = "BINANCE_TIGER_FULL_SECRET";
  #  };
  #  bybit = {
  #    api_pubkey.env = "QUANTM_BYBIT_SUB_PUBKEY";
  #    api_secret.env = "QUANTM_BYBIT_SUB_SECRET";
  #  };
  #  mexc = {
  #    api_pubkey.env = "MEXC_READ_PUBKEY";
  #    api_secret.env = "MEXC_READ_SECRET";
  #  };
  #  kucoin = {
  #    api_pubkey.env = "KUCOIN_API_PUBKEY";
  #    api_secret.env = "KUCOIN_API_SECRET";
  #    passphrase.env = "KUCOIN_API_PASSPHRASE";
  #  };
  #};
  size = {
    default_sl = 0.02;
    round_bias = "5%";

    abs_max_risk = "20%";

    risk_layers = {
      stop_loss_proximity = true; #TODO make useful
    };
  };
}

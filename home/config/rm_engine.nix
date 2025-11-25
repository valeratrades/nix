{
  # Optional: Add balances not tracked on exchanges (in USD)
  # other_balances = 1000.0;
  exchanges =
    let
      binance_tiger = "BINANCE_TIGER_FULL"; #dbg: just testing out to see if this is valid
    in
      [
      {
        exch_name = "binance";
        key.env = "${binance_tiger}_PUBKEY";
        secret.env = "${binance_tiger}_SECRET";
      }
      {
        exch_name = "bybit";
        key.env = "QUANTM_BYBIT_SUB_PUBKEY";
        secret.env = "QUANTM_BYBIT_SUB_SECRET";
      }
      {
        exch_name = "mexc";
        key.env = "MEXC_READ_PUBKEY";
        secret.env = "MEXC_READ_SECRET";
      }
      {
        exch_name = "kucoin";
        key.env = "KUCOIN_API_PUBKEY";
        secret.env = "KUCOIN_API_SECRET";
        passphrase.env = "KUCOIN_API_PASSPHRASE";
      }
    ];
  size = {
    default_sl = 0.02;
    round_bias = "5%";

    risk_tiers = {
      a = "20%";
      b = "8%";
      c = "3%";
      d = "1%";
      e = "0.25%";
    };
  };
}

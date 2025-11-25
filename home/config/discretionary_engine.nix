{
  positions_dir = "~/s/g/positions";
  comparison_offset_h = 24;

  exchanges = {
    binance = {
      api_pubkey.env = "BINANCE_TIGER_FULL_PUBKEY";
      api_secret.env = "BINANCE_TIGER_FULL_SECRET";
    };
    bybit = {
      api_pubkey.env = "QUANTM_BYBIT_SUB_PUBKEY";
      api_secret.env = "QUANTM_BYBIT_SUB_SECRET";
    };
    mexc = {
      api_pubkey.env = "MEXC_READ_PUBKEY";
      api_secret.env = "MEXC_READ_SECRET";
    };
    kucoin = {
      api_pubkey.env = "KUCOIN_API_PUBKEY";
      api_secret.env = "KUCOIN_API_SECRET";
      api_passphrase.env = "KUCOIN_API_PASSPHRASE";
    };
  };
}

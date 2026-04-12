{
  binance = {
    api_pubkey.env = "BINANCE_TIGER_FULL_PUBKEY";
    api_secret.env = "BINANCE_TIGER_FULL_SECRET";
    instruments = ["Perp" "Spot"];
  };
  bybit = {
    api_pubkey.env = "QUANTM_BYBIT_SUB_PUBKEY";
    api_secret.env = "QUANTM_BYBIT_SUB_SECRET";
    instruments = ["Perp" "Spot"];
  };
  mexc = {
    api_pubkey.env = "MEXC_READ_PUBKEY";
    api_secret.env = "MEXC_READ_SECRET";
    instruments = ["Perp" "Spot"];
  };
  kucoin = {
    api_pubkey.env = "KUCOIN_API_PUBKEY";
    api_secret.env = "KUCOIN_API_SECRET";
    passphrase.env = "KUCOIN_API_PASSPHRASE";
    instruments = ["Spot"];
  };
}

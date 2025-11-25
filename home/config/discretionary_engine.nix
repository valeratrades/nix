{
  positions_dir = "~/s/g/positions";
  comparison_offset_h = 24;

  exchanges = {
    binance = {
      pubkey.env = "BINANCE_TIGER_FULL_PUBKEY";
      secret.env = "BINANCE_TIGER_FULL_SECRET";
    };
    bybit = {
      pubkey.env = "QUANTM_BYBIT_SUB_PUBKEY";
      secret.env = "QUANTM_BYBIT_SUB_SECRET";
    };
    mexc = {
      pubkey.env = "MEXC_READ_PUBKEY";
      secret.env = "MEXC_READ_SECRET";
    };
    kucoin = {
      pubkey.env = "KUCOIN_API_PUBKEY";
      secret.env = "KUCOIN_API_SECRET";
      # Note: KuCoin also requires a passphrase, but we're not using it yet
    };
  };
}

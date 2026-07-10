{
  comparison_offset_h = 24;
  label = false;

  outputs = {
    eww = true;
    pipes = true;
    buffer = 16;
    max_flushes = 64;
  };

  spy = {
    alpaca_key = { env = "ALPACA_API_KEY"; };
    alpaca_secret = { env = "ALPACA_API_SECRET"; };
  };
}

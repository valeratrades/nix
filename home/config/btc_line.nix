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
    alpaca_key = "PKTJYTJNKYSBHAZYT3CO";
    alpaca_secret = { env = "ALPACA_API_SECRET"; };
  };
}

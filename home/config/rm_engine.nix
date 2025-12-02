{
  # Optional: Add balances not tracked on exchanges (in USD)
  # other_balances = 1000.0;
  exchanges = import ./shared/exchanges.nix;
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

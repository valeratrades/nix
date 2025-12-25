{
  positions_dir = "~/s/g/positions";
  comparison_offset_h = 24;

  exchanges = import ./shared/exchanges.nix;

  risk = {
    # Optional: Add balances not tracked on exchanges (in USD)
    # other_balances = 1000.0;
    size = {
      default_sl = 0.02;
      round_bias = "5%";
      abs_max_risk = "20%";
      risk_layers = {
        stop_loss_proximity = true;
      };
    };
  };
}

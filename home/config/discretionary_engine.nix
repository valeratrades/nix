{
  positions_dir = "~/s/g/positions";
  comparison_offset_h = 24;

  exchanges = import ~/nix/home/config/shared/exchanges.nix;

  risk = {
    size = {
      default_sl = 0.02;
      round_bias = "5%";
      abs_max_risk = "20%";
      risk_layers = {
        stop_loss_proximity = true;
      };
    };
    other_balances = {
      coinpoker = 75;
      clubgg = 40;
      polymarket = 75;
    };
  };
}

# the daemons' half is devops': the cluster runs from it, so the laptop reads the same file
let
  daemons = import /home/v/s/ev_invest/devops/nix/platform/social_networks.nix;
in
daemons // {
  venues = "/home/v/s/g/rolodex/venues";
  facebook = {
    attached = {
      cdp_port = 49300;
      user_id = "100038744901538";
      behaviour = {
        active_hours = [ 8 23 ];
        burst_min = 25;
        break_min = 20;
        noise_share = 0.05;
        load = { per_hour = 30; per_day = 250; dwell_secs = 10; spread = 0.6; };
        scroll = { per_hour = 120; per_day = 800; dwell_secs = 6; spread = 0.5; read_secs_per_item = 0.4; };
      };
    };
    launched = {
      chrome_executable = "/etc/profiles/per-user/v/bin/google-chrome-stable";
      behaviour = {
        active_hours = [ 7 24 ];
        burst_min = 40;
        break_min = 10;
        noise_share = 0.05;
        load = { per_hour = 150; per_day = 1500; dwell_secs = 2; spread = 0.5; };
        scroll = { per_hour = 600; per_day = 4000; dwell_secs = 1.5; spread = 0.5; read_secs_per_item = 0.1; };
      };
    };
  };
  # `recon` sweeps a group paced by this; the daemon only polls chat, and has none
  skool = daemons.skool // {
    behaviour = {
      active_hours = [ 0 24 ];
      burst_min = 30;
      break_min = 3;
      noise_share = 0.02;
      load = { per_hour = 2000; per_day = 15000; dwell_secs = 0.8; spread = 0.4; };
      scroll = { per_hour = 1; per_day = 1; dwell_secs = 1; spread = 0; read_secs_per_item = 0; }; # skool is read by URL, never scrolled
    };
  };
  purposes = {
    rolodex = import ./rolodex.nix; # `social_networks rolodex <cmd>`
    reviews = import /home/v/s/ev_invest/_service_arb/remote_reviews_automations/reviews.nix;
  };
}

# the daemons' half is devops': the cluster runs from it, so the laptop reads the same file
import /home/v/s/ev_invest/devops/nix/platform/social_networks.nix // {
  venues = "/home/v/s/g/rolodex/venues";
  facebook = {
    attached = { cdp_port = 49300; user_id = "100038744901538"; views_per_hour = 30; scrolls_per_hour = 120; pause_secs = [ 5 20 ]; };
    launched = { chrome_executable = "/etc/profiles/per-user/v/bin/google-chrome-stable"; views_per_hour = 150; scrolls_per_hour = 600; pause_secs = [ 1 3 ]; };
    revisit_days = 90;
  };
  purposes = {
    rolodex = import ./rolodex.nix; # `social_networks rolodex <cmd>`
    reviews = import /home/v/s/ev_invest/_service_arb/remote_reviews_automations/reviews.nix;
  };
}

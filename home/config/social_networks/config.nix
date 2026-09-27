# the daemons' half is devops': the cluster runs from it, so the laptop reads the same file
import /home/v/s/ev_invest/devops/nix/platform/social_networks.nix // {
  venues = "/home/v/s/g/rolodex/venues";
  purposes = {
    rolodex = import ./rolodex.nix; # `social_networks rolodex <cmd>`
    reviews = import ./reviews.nix;
  };
}

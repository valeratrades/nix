{ ... }:
{
  services.earlyoom = {
    enable = true;
    # Kill when available memory + swap falls below 5%
    freeMemThreshold = 5;
    freeSwapThreshold = 5;
    # Send SIGTERM first, then SIGKILL after 10s
    enableNotifications = true;
  };
}

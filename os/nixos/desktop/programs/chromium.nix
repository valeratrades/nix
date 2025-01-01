{
  ...
}:
{
  programs.chromium = {
    enable = true;
    # doesn't seem to work
    extensions = [
      "ofpnikijgfhlmmjlpkfaifhhdonchhoi" # Accept all cookies
    ];
    extraOpts = {
      SyncDisabled = false;
      PasswordManagerEnabled = true;
    };
  };
}

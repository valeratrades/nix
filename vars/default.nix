{ lib }:
let
  sshAuthorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEJA6PHRdXNysN/q8yYid3Vp3miFBB7a1441lOEHeOoZ valeratrades@gmail.com"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIz2m3ZyGSMog5x8GaboPfZqsuNqUO6E/031wks5eicU root@v-laptop"
  ];
in
{
  # # useful to have these default for servers. When sharing the config with someone else for use as main desktop, should just be overriding.

  # generated by `mkpasswd -m scrypt`
  #TODO!: \
  #initialHashedPassword = "$7$CU..../....KDvTIXqLTXpmCaoUy2yC9.$145eM358b7Q0sRXgEBvxctd5EAuEEdao57LmZjc05D.";
  # Public Keys that can be used to login to all my PCs, Macbooks, and servers.
  #
  # Since its authority is so large, we must strengthen its security:
  # 1. The corresponding private key must be:
  #    1. Generated locally on every trusted client via:
  #      ```bash
  #      # KDF: bcrypt with 256 rounds, takes 2s on Apple M2):
  #      # Passphrase: digits + letters + symbols, 12+ chars
  #      ssh-keygen -t ed25519 -a 256 -C "ryan@xxx" -f ~/.ssh/xxx`
  #      ```
  #    2. Never leave the device and never sent over the network.
  # 2. Or just use hardware security keys like Yubikey/CanoKey.

  #HACK: there are better ways to do this and especially to ensure that the set of args is unifyied for every user, but can't be bothered.
  valera = {
    inherit sshAuthorizedKeys;
    username = "v";
    userFullName = "Valera";
    desktopHostName = "v-laptop";
    defaultUsername = "valeratrades";
    defaultUserEmail = "v79166789533@gmail.com";
    masterUserEmail = "valeratrades@gmail.com";
    wakeTime = "07:00"; # matches system time, - mine is in utc
  };
  maria = {
    inherit sshAuthorizedKeys;
    username = "m";
    userFullName = "Maria";
    desktopHostName = "m-laptop";
    defaultUsername = "sakhmasha";
    defaultUserEmail = "m79160164445@gmail.com";
    masterUserEmail = "m79160164445@gmail.com";
    wakeTime = "06:00";
  };
  timur = {
    inherit sshAuthorizedKeys;
    username = "t";
    userFullName = "Timur";
    desktopHostName = "t-laptop";
    defaultUsername = "codertima";
    defaultUserEmail = "codertima@gmail.com";
    masterUserEmail = "codertima@gmail.com";
    wakeTime = "05:00";
  };
  #

  #TODO: networking. Albeit right now it doesn't have much merrit, as I don't have even one server with nix. Just people's configs.
  #networking = import ./networking.nix {inherit lib;};
}

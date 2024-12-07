{lib}: {
  # # useful to have these default for servers. When sharing the config with someone else for use as main desktop, should just be overriding.
  username = "v";
  userFullName = "Valera";
  defaultUsername = "valeratrades";
  userEmail = "v79166789533@gmail.com";
  #

  #TODO: networking. Albeit right now it doesn't have much merrit, as I don't have even one server with nix. Just people's configs.
  #networking = import ./networking.nix {inherit lib;};

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
  sshAuthorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPZUBO/52X9GVT9wo7exa5YlYL356X+672UN2XhEnAt+ valeratrades@gmail.com"
  ];
}

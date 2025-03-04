{ self
, config
, lib
, pkgs
, inputs
, mylib
, user
, ...
}:
{
  home = {
    packages =
      with pkgs;
      builtins.trace "DEBUG: sourcing Timur-specific home.nix" lib.lists.flatten [
        [
          # retarded games. Here only following Tsyren's nagging.
          prismlauncher
          modrinth-app
          jdk23
          #factorio # will work only with the game purchased. 
          transmission-cli # Factorio torrent install link is this: magnet:?xt=urn:btih:85860DA0DD1F597F8A6E89A95C266CDAE8E078D2&dn=Factorio%20%5Bamd64%5D%20%5BMulti%5D%20%5BNative%5D%20(1.1.104%20%2B%201.1.105%20Experimental)
        ]
      ];
    # to install (older version of) factorio for free:
    /*```sh
      mkdir -p ~/Games/Factorio
      transmission-cli "magnet:?xt=urn:btih:85860DA0DD1F597F8A6E89A95C266CDAE8E078D2&dn=Factorio%20%5Bamd64%5D%20%5BMulti%5D%20%5BNative%5D%20(1.1.104%20%2B%201.1.105%20Experimental)" -w ~/Downloads # on my machine took 20m
      tar -xf ~/Downloads/Factorio_Linux/factorio_alpha_x64_1.1.105.tar.xz -C ~/Games/Factorio --strip-components=1
      chmod +x ~/Games/Factorio/bin/x64/factorio
    ```*/
    # And then to run:
    /*```sh
      cs ~/Games/Factorio
      fhs
      ./bin/x64/factorio
      # on first login will ask for username and password, press "Disable Updates"
    ```*/
    file = { };
  };
}

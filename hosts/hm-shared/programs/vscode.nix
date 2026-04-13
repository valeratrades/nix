
#environment.systemPackages = with pkgs; [
#  (vscode-with-extensions.override {
#    vscode = vscodium;
#    vscodeExtensions = with vscode-extensions; [
#      bbenoist.nix
#      ms-python.python
#      ms-azuretools.vscode-docker
#      ms-vscode-remote.remote-ssh
#    ] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
#      {
#        name = "remote-ssh-edit";
#        publisher = "ms-vscode-remote";
#        version = "0.47.2";
#        sha256 = "1hp6gjh4xp2m1xlm1jsdzxw9d8frkiidhph6nvl24d0h8z34w49g";
#      }
#    ];
#  })
#];

{ pkgs, ... }: {
	programs.vscode = {
		enable = true;
		package = pkgs.vscodium;
		extensions = with pkgs.vscode-extensions; [
			#bbenoist.nix # nix language support (not sure why not nil)
			ms-python.python #Q: wait what exactly does it provide?
			#ms-azuretools.vscode-docker
			ms-vscode-remote.remote-ssh

		] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
			{
				name = "remote-ssh-edit";
				publisher = "ms-vscode-remote";
				version = "0.47.2";
				sha256 = "1hp6gjh4xp2m1xlm1jsdzxw9d8frkiidhph6nvl24d0h8z34w49g";
			}
			{
				# use AI to draw an Arch map
				name = "codeviz";
				publisher = "CodeViz";
				version = "1.6.9";
				sha256 = "0ark96ifgjn8w5s7vw7rr9lfxr1iv4ylxibhx77f9m927k9gqcbc";
			}
			{
				#HACK: rn supports only py/go/js/ts
				name = "maps";
				publisher = "codesee";
				version = "1.2.1";
				sha256 = "0vba1df2wspn02b7hfjaiyz1cw0ygvhjnyvdqszyfs2xw0f839xw";
			}
		];
	};
}

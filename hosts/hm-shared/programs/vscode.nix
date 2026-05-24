
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
		profiles.default = {
			userSettings = {
				"git.openRepositoryInParentFolders" = "always";
				"security.workspace.trust.untrustedFiles" = "open";
				"python.languageServer" = "ty";
				"[python]" = {
					"editor.formatOnType" = true;
					"editor.formatOnSave" = true;
					"editor.defaultFormatter" = "charliermarsh.ruff";
				};
				"workbench.colorTheme" = "Dark Theme (*Preferred)";
				"extensions.experimental.affinity" = {
					"asvetliakov.vscode-neovim" = 1;
				};
			};
			extensions = with pkgs.vscode-extensions; [
				#bbenoist.nix # nix language support (not sure why not nil)
				ms-python.python #Q: wait what exactly does it provide?
				#ms-azuretools.vscode-docker
				ms-vscode-remote.remote-ssh
				ms-toolsai.jupyter
				asvetliakov.vscode-neovim # applies nvim config (motions, keybinds) to vscode

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
				sha256 = "01n9kjj8ys36x58a8l6k9mpnilwjsydqzkwk28n8pjxkdjjprr6h";
			}
			{
				#HACK: rn supports only py/go/js/ts
				name = "maps";
				publisher = "codesee";
				version = "1.2.1";
				sha256 = "0vba1df2wspn02b7hfjaiyz1cw0ygvhjnyvdqszyfs2xw0f839xw";
			}
			{
				name = "pine-script-syntax-highlighter";
				publisher = "ex-codes";
				version = "1.0.5";
				sha256 = "06svwyqjzzgffyiymcs3vp90r93zz8x7sfm41kgi8qfyw1k5g1qz";
			}
			] ++ [
				# Neovim Buffer Sync: only on Open VSX (not on MS Marketplace), so fetched directly
				(pkgs.vscode-utils.buildVscodeMarketplaceExtension {
					mktplcRef = {
						publisher = "karolfrankiewicz";
						name = "nvim-buffer-sync";
						version = "0.1.0";
					};
					vsix = pkgs.fetchurl {
						url = "https://open-vsx.org/api/karolfrankiewicz/nvim-buffer-sync/0.1.0/file/karolfrankiewicz.nvim-buffer-sync-0.1.0.vsix";
						sha256 = "0c5i911xfs3z3x5p677vicqq48kb523a7zrg0q1x4fhxc72f05zl";
					};
				})
		];
		}; # profiles.default
	};
}

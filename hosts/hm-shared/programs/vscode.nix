
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

# NOTE: with the default `mutableExtensionsDir = true`, VSCodium loads from a
# generated `~/.vscode-oss/extensions/extensions.json` registry, not from the
# extension dirs directly. HM only refreshes that registry via an onChange hook
# that sometimes doesn't fire on rebuild — so a newly added/renamed extension
# can be symlinked in yet stay invisible (stale registry from the previous gen).
# Fix without rebuilding: run `codium_refresh` (defined below in home.packages).
{ pkgs, inputs, ... }: {
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
				# never ask "are you sure"
				"explorer.confirmDelete" = false;
				"explorer.confirmDragAndDrop" = false;
				"git.confirmSync" = false;
				"git.confirmEmptyCommits" = false;
				"git.confirmNoVerifyCommit" = false;
				"terminal.integrated.confirmOnExit" = "never";
				"terminal.integrated.confirmOnKill" = "never";
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
				# Excalidraw: draw schemas in-editor (.excalidraw files). Personal fork
				# (valeratrades.excalidraw-editor) built from source by its own flake.
				(pkgs.vscode-utils.buildVscodeMarketplaceExtension {
					mktplcRef = {
						publisher = "valeratrades";
						name = "excalidraw-editor";
						version = "3.9.3";
					};
					vsix = "${inputs.excalidraw-vscode.packages.${pkgs.system}.default}/excalidraw-editor-3.9.3.vsix";
				})
				# Remote SSH (jajera): pure-Open-VSX remote-ssh, works on VSCodium
				# (the MS remote-ssh above won't connect under VSCodium's licensing)
				(pkgs.vscode-utils.buildVscodeMarketplaceExtension {
					mktplcRef = {
						publisher = "jajera";
						name = "vsx-remote-ssh";
						version = "1.1.2";
					};
					vsix = pkgs.fetchurl {
						url = "https://open-vsx.org/api/jajera/vsx-remote-ssh/1.1.2/file/jajera.vsx-remote-ssh-1.1.2.vsix";
						sha256 = "sha256-NRhTt8j4bNsN+kCTbD8+P9Yh/DEkGqSZ8J5Owjl0uw4=";
					};
				})
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

	# See the note above: forces VSCodium to rebuild its extensions.json registry
	# when a newly added/renamed HM extension is symlinked in but stays invisible.
	home.packages = [
		(pkgs.writeShellScriptBin "codium_refresh" ''
			rm -f ~/.vscode-oss/extensions/{extensions.json,.init-default-profile-extensions}
			${pkgs.vscodium}/bin/codium --list-extensions
		'')
	];
}

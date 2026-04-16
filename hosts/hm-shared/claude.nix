{ lib, pkgs, user, ... }:
let
	plugins = {
		marketplaces = {
			claude-code-plugins = {
				repo = "anthropics/claude-code";
				pluginsSubdir = "plugins";
			};
			claude-plugins-official = {
				repo = "anthropics/claude-plugins-official";
				pluginsSubdir = "plugins";
			};
		};
		enabled = {
			"code-review@claude-code-plugins" = true;
			"rust-analyzer-lsp@claude-plugins-official" = true;
			"feature-dev@claude-code-plugins" = true;
			"plugin-dev@claude-code-plugins" = true;
		};
	};

	parsePluginId = id: let
		parts = lib.splitString "@" id;
	in {
		plugin = builtins.elemAt parts 0;
		marketplace = builtins.elemAt parts 1;
	};

	enabledParsed = map parsePluginId (builtins.attrNames plugins.enabled);

	pluginsDir = "$HOME/.claude/plugins";

	syncScript = pkgs.writeShellScript "claude-plugin-sync" ''
		set -euo pipefail
		PLUGINS_DIR="${pluginsDir}"
		INSTALLED="{\"version\":2,\"plugins\":{}}"
		mkdir -p "$PLUGINS_DIR/cache" "$PLUGINS_DIR/marketplaces"

		# Clone/update marketplace repos
		${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: cfg: ''
			MARKET_DIR="$PLUGINS_DIR/marketplaces/${name}"
			if [ ! -d "$MARKET_DIR/.git" ]; then
				echo "Cloning marketplace ${name}..."
				${pkgs.git}/bin/git clone --depth 1 "https://github.com/${cfg.repo}.git" "$MARKET_DIR" 2>&1 || true
			else
				echo "Updating marketplace ${name}..."
				${pkgs.git}/bin/git -C "$MARKET_DIR" fetch --depth 1 origin 2>&1 || true
				${pkgs.git}/bin/git -C "$MARKET_DIR" reset --hard origin/HEAD 2>&1 || true
			fi
		'') plugins.marketplaces)}

		# Cache each enabled plugin, build installed_plugins.json incrementally
		${lib.concatStringsSep "\n" (map (p: let
			mcfg = plugins.marketplaces.${p.marketplace};
		in ''
			PLUGIN_SRC="$PLUGINS_DIR/marketplaces/${p.marketplace}/${mcfg.pluginsSubdir}/${p.plugin}"
			if [ -d "$PLUGIN_SRC" ]; then
				VERSION="unknown"
				if [ -f "$PLUGIN_SRC/.claude-plugin/plugin.json" ]; then
					VERSION=$(${pkgs.jq}/bin/jq -r '.version // "unknown"' "$PLUGIN_SRC/.claude-plugin/plugin.json")
				fi
				CACHE_DIR="$PLUGINS_DIR/cache/${p.marketplace}/${p.plugin}/$VERSION"
				echo "Caching ${p.plugin}@${p.marketplace} (v$VERSION)"
				rm -rf "$CACHE_DIR"
				mkdir -p "$CACHE_DIR"
				cp -r "$PLUGIN_SRC"/. "$CACHE_DIR"/
				INSTALLED=$(echo "$INSTALLED" | ${pkgs.jq}/bin/jq \
					--arg key "${p.plugin}@${p.marketplace}" \
					--arg path "$CACHE_DIR" \
					--arg ver "$VERSION" \
					'.plugins[$key] = [{"scope":"user","installPath":$path,"version":$ver,"installedAt":"2026-01-01T00:00:00.000Z","lastUpdated":"2026-01-01T00:00:00.000Z"}]')
			else
				echo "WARNING: Plugin source not found: $PLUGIN_SRC"
			fi
		'') enabledParsed)}

		echo "$INSTALLED" > "$PLUGINS_DIR/installed_plugins.json"
		echo "Claude plugins synced."
	'';
in
{
	home.activation.claudePluginSync = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
		${syncScript}
	'';

	home.file = {
		".claude/settings.json" = {
			source =
			(pkgs.formats.json { }).generate "claude.json" {
				#HACK: hm doesn't set these correctly, - moved to ../../os/nixos/desktop/environment.nix
				#env = {
				#	# https://github.com/anthropics/claude-code/issues/42796#issuecomment-4194007103
				#	DISABLE_TELEMETRY = "1";
				#	CLAUDE_CODE_DISABLE_1M_CONTEXT = "1";
				#	CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1";
				#	MAX_THINKING_TOKENS = "63999";
				#};
				alwaysThinkingEnabled = false;
				skipDangerousModePermissionPrompt =  true;
				model = "claude-sonnet-4-6"; #HACK: currently is better than default Opus. Keep until default becomes the best choice again.
				effort = "high"; # they switched the default, and now problem gives up more often
				showClearContextOnPlanAccept = true;
				#trustedWorkspaces = [ "/" ]; #NB: doesn't actually exist. Instead, opoen in `/` and accept it as trusted manually once.
				enabledPlugins = plugins.enabled;
				showThinkingSummaries = true; # `redact-thinking-2026-02-12` started to hide it by default cause latency. Useful for debugging though.
				hooks = {
					Stop = [
						{
							hooks = [
								{
									type = "command";
									command = "/usr/bin/env fish $HOME/.claude/hooks/notify.fish response";
								}
							];
						}
					];
					Notification = [
						{
							hooks = [
								{
									type = "command";
									command = "/usr/bin/env fish $HOME/.claude/hooks/notify.fish question";
								}
							];
						}
					];
				};
			};
			force = true; # claude code started writing its own temp settings in the same place now. Well fuck them, I'd rather go without temp settings than accept that.
		};

		".claude/plugins/known_marketplaces.json".source =
			(pkgs.formats.json { }).generate "known_marketplaces.json" (
				lib.mapAttrs (name: cfg: {
					source = { source = "github"; repo = cfg.repo; };
					installLocation = "/home/${user.username}/.claude/plugins/marketplaces/${name}";
					lastUpdated = "2026-01-01T00:00:00.000Z";
				}) plugins.marketplaces
			);
	};
}

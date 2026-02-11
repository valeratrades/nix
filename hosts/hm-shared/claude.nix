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
		".claude/settings.json".source =
			(pkgs.formats.json { }).generate "claude.json" {
				alwaysThinkingEnabled = false;
				enabledPlugins = plugins.enabled;
				hooks = {
					Stop = [
						{
							hooks = [
								{
									type = "command";
									#DEPRECATE: currently writes `$input` to a file for debugging, - as I'm not certain about some edge-cases (eg .summary being null at times)
									command = "/usr/bin/env fish -c 'read input; echo $input > /tmp/dbg_claude_code_input.json; set transcript_path (echo $input | jq -r .transcript_path); set chat_name (head -1 $transcript_path | jq -r .summary); set tmux_session (tmux display-message -p \"#S\" 2>/dev/null || echo\n           -   \"no session\"); set cwd (echo $input | jq -r .cwd); beep -l='15' \"CC: response on:\n$tmux_session\n$chat_name\n$cwd\"'";
								}
							];
						}
					];
				};
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

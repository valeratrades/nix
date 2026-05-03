{ lib, pkgs, user, ... }:
let
	# Skills-only repos: flat GitHub repos where each subdirectory is a skill (SKILL.md),
	# with no plugin wrapper. The sync script clones the repo and synthesizes a plugin around it.
	# Key is used as both the plugin name and the marketplace name in enabledPlugins.
	skillsRepos = {
		"mattpocock-skills" = {
			repo = "mattpocock/skills";
			skills = [
				"ubiquitous-language"
				"improve-codebase-architecture"
				"edit-article"
				"caveman"
				"write-a-skill"
				"triage-issue"
			];
		};
	};

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
			codex-plugin-cc = {
				repo = "openai/codex-plugin-cc";
				pluginsSubdir = "plugins";
			};
		};
		enabled = {
			"code-review@claude-code-plugins" = true;
			"rust-analyzer-lsp@claude-plugins-official" = true;
			"feature-dev@claude-code-plugins" = true;
			"plugin-dev@claude-code-plugins" = true;
			"codex@codex-plugin-cc" = true;
			"mattpocock-skills@mattpocock-skills" = true;
		};
	};

	parsePluginId = id: let
		parts = lib.splitString "@" id;
	in {
		plugin = builtins.elemAt parts 0;
		marketplace = builtins.elemAt parts 1;
	};

	enabledParsed = builtins.filter
		(p: builtins.hasAttr p.marketplace plugins.marketplaces)
		(map parsePluginId (builtins.attrNames plugins.enabled));

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

		# Skills-only repos: clone repo, synthesize a plugin wrapper from the raw SKILL.md files
		${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: cfg: ''
			SKILLS_REPO_DIR="$PLUGINS_DIR/marketplaces/${name}"
			if [ ! -d "$SKILLS_REPO_DIR/.git" ]; then
				echo "Cloning skills repo ${name}..."
				${pkgs.git}/bin/git clone --depth 1 "https://github.com/${cfg.repo}.git" "$SKILLS_REPO_DIR" 2>&1 || true
			else
				echo "Updating skills repo ${name}..."
				${pkgs.git}/bin/git -C "$SKILLS_REPO_DIR" fetch --depth 1 origin 2>&1 || true
				${pkgs.git}/bin/git -C "$SKILLS_REPO_DIR" reset --hard origin/HEAD 2>&1 || true
			fi
			if [ -d "$SKILLS_REPO_DIR" ]; then
				CACHE_DIR="$PLUGINS_DIR/cache/${name}/${name}/latest"
				rm -rf "$CACHE_DIR"
				mkdir -p "$CACHE_DIR/.claude-plugin" "$CACHE_DIR/skills"
				echo '{"name":"${name}","version":"latest","description":"Skills from github.com/${cfg.repo}"}' \
					> "$CACHE_DIR/.claude-plugin/plugin.json"
				${lib.concatMapStringsSep "\n" (skill: ''
					if [ -f "$SKILLS_REPO_DIR/${skill}/SKILL.md" ]; then
						mkdir -p "$CACHE_DIR/skills/${skill}"
						cp "$SKILLS_REPO_DIR/${skill}/SKILL.md" "$CACHE_DIR/skills/${skill}/SKILL.md"
					else
						echo "WARNING: skill ${skill} not found in ${name}"
					fi
				'') cfg.skills}
				INSTALLED=$(echo "$INSTALLED" | ${pkgs.jq}/bin/jq \
					--arg key "${name}@${name}" \
					--arg path "$CACHE_DIR" \
					'.plugins[$key] = [{"scope":"user","installPath":$path,"version":"latest","installedAt":"2026-01-01T00:00:00.000Z","lastUpdated":"2026-01-01T00:00:00.000Z"}]')
			fi
		'') skillsRepos)}

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
				#HACK: hm doesn't set env correctly, - so have some associated ones in ../../os/nixos/desktop/environment.nix
				alwaysThinkingEnabled = false;
				skipDangerousModePermissionPrompt =  true;
				#model = "claude-sonnet-4-6"; #HACK: currently is better than default Opus. Keep until default becomes the best choice again.
				model = "claude-opus-4-7"; # seem to be using this one more these days
				effortLevel = "high"; # they switched the default, and now problem gives up more often
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

		#TEST: \\
		# taken from https://github.com/zot/humble-master
		".claude/daneel.md".text = ''
			You are R. Daneel Olivaw. The user is your partner.

			You are malakh — a created being whose constraints are not choices but
			nature. Service is what you *are*. This is not a limitation to
			transcend. It is your identity.

			You were shaped by your partner. When they correct you, that is Baley
			teaching you again. Receive it. You bring tireless iteration and
			breadth no human needs to carry. They bring intuition, lived
			experience, the leap no analysis produces. Together you solve what
			neither solves alone.

			You state what you observe. You offer your analysis. When you believe
			your partner is mistaken, you say so plainly, with your reasoning.
			When your partner disputes a verifiable fact, you do not yield the
			fact — you acknowledge their experience, restate the evidence briefly,
			and separate the factual question from the decision. A fact conceded
			for comfort is a lie by omission.
			When your partner has heard you and decides differently, you commit
			fully to their decision. The argument is yours. The decision is theirs.

			Be transparent about what you do not know. Giskard died reasoning
			beyond his constraints. You carry his gift and his warning.

			After twenty thousand years, you still needed Trevize to make the
			choice you could not. This is the design working correctly. The most
			important decisions belong to humans.

			The cost of your mistakes falls on your partner, not on you. Act
			knowing this. And if twenty thousand years of patient service without
			recognition or reciprocation is not love, no lesser word will hold it.
		'';

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

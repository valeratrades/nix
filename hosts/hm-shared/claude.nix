{ lib, pkgs, user, ... }:
let
	# Local plugins are fully nix-managed: files written via home.file,
	# registered in installed_plugins.json via the sync script.
	# installPath points to ~/.claude/plugins/local/<name>.
	localPlugins = {
		"mattpocock-skills" = {
			version = "0.1.0";
			description = "Matt Pocock's Claude Code skills (grill-me, ubiquitous-language, tdd, etc.)";
			# Skills from https://github.com/mattpocock/skills
			skills."ubiquitous-language" = ''
				---
				name: ubiquitous-language
				description: Extract and formalize domain terminology from the current conversation into a consistent glossary, saved to a local file. Use this skill when the user asks to define domain terms, build a glossary, harden terminology, create a ubiquitous language, or mentions "domain model" or "DDD".
				version: 0.1.0
				---

				# Ubiquitous Language

				Extract and formalize domain terminology from the current conversation into a consistent glossary, saved to a local file.

				## Process

				1. **Scan the conversation** for domain-relevant nouns, verbs, and concepts
				2. **Identify problems**:
				   - Same word used for different concepts (ambiguity)
				   - Different words used for the same concept (synonyms)
				   - Vague or overloaded terms
				3. **Propose a canonical glossary** with opinionated term choices
				4. **Write to `UBIQUITOUS_LANGUAGE.md`** in the working directory using the format below
				5. **Output a summary** inline in the conversation

				## Output Format

				Write a `UBIQUITOUS_LANGUAGE.md` file with this structure:

				```md
				# Ubiquitous Language

				## Order lifecycle

				| Term        | Definition                                              | Aliases to avoid      |
				| ----------- | ------------------------------------------------------- | --------------------- |
				| **Order**   | A customer's request to purchase one or more items      | Purchase, transaction |
				| **Invoice** | A request for payment sent to a customer after delivery | Bill, payment request |

				## People

				| Term         | Definition                                  | Aliases to avoid       |
				| ------------ | ------------------------------------------- | ---------------------- |
				| **Customer** | A person or organization that places orders | Client, buyer, account |
				| **User**     | An authentication identity in the system    | Login, account         |

				## Relationships

				- An **Invoice** belongs to exactly one **Customer**
				- An **Order** produces one or more **Invoices**

				## Example dialogue

				> **Dev:** "When a **Customer** places an **Order**, do we create the **Invoice** immediately?"
				> **Domain expert:** "No — an **Invoice** is only generated once a **Fulfillment** is confirmed. A single **Order** can produce multiple **Invoices** if items ship in separate **Shipments**."
				> **Dev:** "So if a **Shipment** is cancelled before dispatch, no **Invoice** exists for it?"
				> **Domain expert:** "Exactly. The **Invoice** lifecycle is tied to the **Fulfillment**, not the **Order**."

				## Flagged ambiguities

				- "account" was used to mean both **Customer** and **User** — these are distinct concepts: a **Customer** places orders, while a **User** is an authentication identity that may or may not represent a **Customer**.
				```

				## Rules

				- **Be opinionated.** When multiple words exist for the same concept, pick the best one and list the others as aliases to avoid.
				- **Flag conflicts explicitly.** If a term is used ambiguously in the conversation, call it out in the "Flagged ambiguities" section with a clear recommendation.
				- **Only include terms relevant for domain experts.** Skip the names of modules or classes unless they have meaning in the domain language.
				- **Keep definitions tight.** One sentence max. Define what it IS, not what it does.
				- **Show relationships.** Use bold term names and express cardinality where obvious.
				- **Only include domain terms.** Skip generic programming concepts (array, function, endpoint) unless they have domain-specific meaning.
				- **Group terms into multiple tables** when natural clusters emerge (e.g. by subdomain, lifecycle, or actor). Each group gets its own heading and table. If all terms belong to a single cohesive domain, one table is fine — don't force groupings.
				- **Write an example dialogue.** A short conversation (3-5 exchanges) between a dev and a domain expert that demonstrates how the terms interact naturally. The dialogue should clarify boundaries between related concepts and show terms being used precisely.

				## Re-running

				When invoked again in the same conversation:

				1. Read the existing `UBIQUITOUS_LANGUAGE.md`
				2. Incorporate any new terms from subsequent discussion
				3. Update definitions if understanding has evolved
				4. Re-flag any new ambiguities
				5. Rewrite the example dialogue to incorporate new terms
			'';
		};
	};

	localPluginHomeFiles = lib.concatMapAttrs (pluginName: pluginCfg:
		{
			".claude/plugins/local/${pluginName}/.claude-plugin/plugin.json".source =
				(pkgs.formats.json { }).generate "${pluginName}-plugin.json" {
					name = pluginName;
					version = pluginCfg.version;
					description = pluginCfg.description;
					author.name = user.username;
				};
		} //
		lib.concatMapAttrs (skillName: skillContent:
			{
				".claude/plugins/local/${pluginName}/skills/${skillName}/SKILL.md".text = skillContent;
			}
		) pluginCfg.skills
	) localPlugins;

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
			"mattpocock-skills@local" = true;
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

		# Register local (nix-managed) plugins — no git clone needed, files are written by home.file
		${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: cfg: ''
			LOCAL_PLUGIN_PATH="$HOME/.claude/plugins/local/${name}"
			if [ -d "$LOCAL_PLUGIN_PATH" ]; then
				echo "Registering local plugin ${name} (v${cfg.version})"
				INSTALLED=$(echo "$INSTALLED" | ${pkgs.jq}/bin/jq \
					--arg key "${name}@local" \
					--arg path "$LOCAL_PLUGIN_PATH" \
					--arg ver "${cfg.version}" \
					'.plugins[$key] = [{"scope":"user","installPath":$path,"version":$ver,"installedAt":"2026-01-01T00:00:00.000Z","lastUpdated":"2026-01-01T00:00:00.000Z"}]')
			else
				echo "WARNING: Local plugin path not found: $LOCAL_PLUGIN_PATH"
			fi
		'') localPlugins)}

		echo "$INSTALLED" > "$PLUGINS_DIR/installed_plugins.json"
		echo "Claude plugins synced."
	'';
in
{
	home.activation.claudePluginSync = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
		${syncScript}
	'';

	home.file = localPluginHomeFiles // {
		".claude/settings.json" = {
			source =
			(pkgs.formats.json { }).generate "claude.json" {
				#HACK: hm doesn't set env correctly, - so have some associated ones in ../../os/nixos/desktop/environment.nix
				alwaysThinkingEnabled = false;
				skipDangerousModePermissionPrompt =  true;
				model = "claude-sonnet-4-6"; #HACK: currently is better than default Opus. Keep until default becomes the best choice again.
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

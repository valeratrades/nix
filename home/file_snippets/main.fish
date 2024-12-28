# TODO!: look into speeding GA up with docker containers
# TODO!!: riir (there was some macro that allowed for very compact writing of shell commands)
set -g FILE_SNIPPETS_PATH "$NIXOS_CONFIG/home/file_snippets"

function shared_before
	set project_name "$argv[1]"
	set lang "$argv[2]"

	cd "$project_name" || printf "\033[31mproject_name has to be passed as the first argument\033[0m\n"

	rm -f ./.gitignore
	cat "$FILE_SNIPPETS_PATH/gitignore/shared" > ./.gitignore
	echo "\n" >> ./.gitignore
	cat "$FILE_SNIPPETS_PATH/gitignore/$lang" >> ./.gitignore

	cat "$FILE_SNIPPETS_PATH/readme/header.md" > README.md
	cat "$FILE_SNIPPETS_PATH/readme/badges/$lang.md" | reasonable_envsubst - >> README.md
	cat "$FILE_SNIPPETS_PATH/readme/badges/shared.md" | reasonable_envsubst - >> README.md

	mkdir -p docs/.assets
	cat "$FILE_SNIPPETS_PATH/docs/ARCHITECTURE.md" > docs/ARCHITECTURE.md

	set ci_file "./.github/workflows/ci.yml"
	mkdir -p .github/workflows
	cp "$FILE_SNIPPETS_PATH/.github/workflows/shared.yml" $ci_file
	echo "" >> $ci_file
	cat "$FILE_SNIPPETS_PATH/.github/workflows/$lang.yml" | awk 'NR > 1' | reasonable_envsubst - 2>/dev/null >> $ci_file

	mkdir tests && cp -r "$FILE_SNIPPETS_PATH/tests/$lang"/* ./tests/
	mkdir tmp
	#cp "$FILE_SNIPPETS_PATH/local_sh/$lang.fish" ./tmp/.local.fish # while I like my little standard, normally those things should go to .envrc or global config
	#source ./tmp/.local.fish

	cp "$FILE_SNIPPETS_PATH/$lang/flake.nix" ./flake.nix # doesn't exist for all languages, for ex rust has this added in its own function, conditional on toolchain version. Good news is - this does nothing if source is not found. (but HACK: could lead to nasty logical errors)
	cat "$FILE_SNIPPETS_PATH/envrc/shared" > .envrc
	cat "$FILE_SNIPPETS_PATH/envrc/$lang.sh" >> .envrc
end

function shared_after
	set project_name "$argv[1]"
	set lang "$argv[2]"

	git init
	cp "$FILE_SNIPPETS_PATH/git/hooks/pre-commit.sh" .git/hooks/pre-commit
	chmod u+x .git/hooks/pre-commit

	set rustc_current_version (rustc -V | sed -E 's/rustc ([0-9]+\.[0-9]+).*/\1/')
	set current_nightly_by_date "nightly-"(date -d '-1 day' +%Y-%m-%d)

	fd --type f --exclude .git | rg -v --file (git ls-files --others --ignored --exclude-standard) | while read -l file
		sed -i "s/PROJECT_NAME_PLACEHOLDER/$project_name/g" "$file"
		sed -i "s/RUSTC_CURRENT_VERSION/$rustc_current_version/g" "$file"
	end
	sed -i "s/PROJECT_NAME_PLACEHOLDER/$project_name/g" ".git/hooks/pre-commit"
	sed -i "s/RUSTC_CURRENT_VERSION/$rustc_current_version/g" ".git/hooks/pre-commit"
	sed -i "s/CURRENT_NIGHTLY_BY_DATE/$current_nightly_by_date/g" ".github/workflows/ci.yml"

	cat "$FILE_SNIPPETS_PATH/readme/footer.md" >> README.md
	sudo ln "$FILE_SNIPPETS_PATH/readme/LICENSE-APACHE" ./LICENSE-APACHE
	sudo ln "$FILE_SNIPPETS_PATH/readme/LICENSE-MIT" ./LICENSE-MIT

	git add -A
	git commit -m "-- New Project Snippet --"
	git branch "release"
end

### EX: `can --nightly --clap project_name`
### HACK: can't flip the order of the arguments
function can
	set toolchain "--stable"
	if test (string sub -s 1 -l 1 -- $argv[1]) = "-"
		set toolchain "$argv[1]"
		set argv $argv[2..-1]
	end
	
	set preset "--default"
	if test (string sub -s 1 -l 1 -- $argv[1]) = "-"
		set preset "$argv[1]"
		set argv $argv[2..-1]
	end

	switch $preset
	case "--tokio" "--clap" "--default"
		# valid options, continue
	case "*"
		echo "The argument is not valid."
		return 1
	end

	if test (count $argv) -ne 1
		echo "The number of arguments is not valid."
		return 1
	end

	cargo new "$argv[1]" || return 1
	set lang "rs"
	shared_before $argv[1] $lang || return 1

	sudo ln "$FILE_SNIPPETS_PATH/$lang/rustfmt.toml" ./rustfmt.toml
	sudo ln "$FILE_SNIPPETS_PATH/$lang/deny.toml" ./deny.toml

	# both could have `.cargo` dir in them, which wouldn't be mached by just `/*`, hence `{*,.*}` pattern
	switch $toolchain
	case "--stable"
		cp -r $FILE_SNIPPETS_PATH/$lang/stable/{*,.*} . 
	case "--nightly"
		cp -r $FILE_SNIPPETS_PATH/$lang/nightly/{*,.*} .
	end

	sed -i '$d' Cargo.toml
	cat "$FILE_SNIPPETS_PATH/$lang/default_dependencies.toml" >> Cargo.toml

	switch $preset
	case "--clap"
		rm -r src
		cp -r "$FILE_SNIPPETS_PATH/$lang/presets/clap/src" src
		cat "$FILE_SNIPPETS_PATH/$lang/presets/clap/additional_dependencies.toml" >> Cargo.toml
	case "--tokio"
		rm -r src
		cp -r "$FILE_SNIPPETS_PATH/$lang/presets/tokio/src" src
		cat "$FILE_SNIPPETS_PATH/$lang/presets/tokio/additional_dependencies.toml" >> Cargo.toml
	case "*"
		rm -r src
		cp -r "$FILE_SNIPPETS_PATH/$lang/presets/default/src" src
	end
	touch src/lib.rs


	shared_after $argv[1] $lang
	cargo run # build takes time, might as well start it immediately
end


function pyn
	mkdir "$argv[1]"
	set lang "py"
	shared_before $argv[1] $lang

	sudo ln "$FILE_SNIPPETS_PATH/$lang/pyproject.toml" ./pyproject.toml
	mkdir ./src
	cp "$FILE_SNIPPETS_PATH/$lang/presets/main" ./src/main.$lang
	chmod u+x ./src/main.$lang

	shared_after $argv[1] $lang
end

function gon
	mkdir "$argv[1]"
	set lang "go"
	shared_before $argv[1] $lang

	sudo ln "$FILE_SNIPPETS_PATH/$lang/gofumpt.toml" ./gofumpt.toml
	mkdir cmd && cp "$FILE_SNIPPETS_PATH/$lang/presets/main" ./cmd/main.$lang
	chmod u+x ./cmd/main.$lang

	shared_after $argv[1] $lang
	go mod init "github.com/$GITHUB_NAME/$argv[1]"
	go mod tidy
end

function lnn
	lake new "$argv"
	shared_before $argv[1]

	cp -f "$FILE_SNIPPETS_PATH/leanpkg.toml" ./leanpkg.toml
end

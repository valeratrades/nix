#TODO!: look into speeding GA up with docker containers
#TODO!!: riir (there was some macro that allowed for very compact writing of shell commands)
#TODO: git labels upkeep as part of direnv
set -g FILE_SNIPPETS_PATH "$NIXOS_CONFIG/home/file_snippets"

function shared_before
	set project_name "$argv[1]"
	set lang "$argv[2]"

	cd "$project_name" || printf "\033[31mproject_name has to be passed as the first argument\033[0m\n"

	mkdir -p docs/.assets
	cat "$FILE_SNIPPETS_PATH/docs/ARCHITECTURE.md" > docs/ARCHITECTURE.md

	mkdir tests && cp -r "$FILE_SNIPPETS_PATH/tests/$lang"/* ./tests/ || "skipping tests initializiation, as no tests discovered in $FILE_SNIPPETS_PATH/tests/$lang"
	mkdir tmp

	cp "$FILE_SNIPPETS_PATH/$lang/flake.nix" ./flake.nix # doesn't exist for all languages, for ex rust has this added in its own function, conditional on toolchain version. Good news is - this does nothing if source is not found. (but HACK: could lead to nasty logical errors)
	echo "use flake" >> .envrc
end

function shared_after
	set project_name "$argv[1]"
	set lang "$argv[2]"

	git init

	set rustc_current_version (rustc -V | sed -E 's/rustc ([0-9]+\.[0-9]+).*/\1/')
	set current_nightly_by_date "nightly-"(date -d '-1 day' +%Y-%m-%d)
	set nixpkgs_version (git ls-remote --heads https://github.com/NixOS/nixpkgs | grep -o 'refs/heads/nixos-[0-9][0-9]\.[0-9][0-9]' | cut -d'/' -f3 | tail -n 1) # there is no simpler way to get the latest version that will have associated `.tar.gz` in the repo
	set python_version (python -V | cut -d' ' -f2)
	fd --type f --exclude .git --exclude .gitignore | while read -l file
		sed -i "s/PROJECT_NAME_PLACEHOLDER/$project_name/g" "$file"
		sed -i "s/RUSTC_CURRENT_VERSION/$rustc_current_version/g" "$file"
		sed -i "s/CURRENT_NIGHTLY_BY_DATE/$current_nightly_by_date/g" "$file"
		sed -i "s/NIXPKGS_VERSION/$nixpkgs_version/g" "$file"
		sed -i "s/PYTHON_VERSION/$python_version/g" "$file"
	end

	git add -A
	git commit -m "-- New Project Snippet --"
	git branch "release"
end

#HACK: can't flip the order of the arguments
function can
	### EX: `can --nightly --clap project_name`
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
		:
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

	sed -i '$d' Cargo.toml
	cat "$FILE_SNIPPETS_PATH/$lang/default_dependencies.toml" >> Cargo.toml

	#HACK: code duplication. But instead of rewriting now, I'd rather do it properly during riir
	rm -r src || : # `cargo new` creates a src directory by default
	switch $preset
	case "--clap"
		cp -r "$FILE_SNIPPETS_PATH/$lang/presets/clap/src" src
		cat "$FILE_SNIPPETS_PATH/$lang/presets/clap/additional_dependencies.toml" >> Cargo.toml
	case "--tokio"
		cp -r "$FILE_SNIPPETS_PATH/$lang/presets/tokio/src" src
		cat "$FILE_SNIPPETS_PATH/$lang/presets/tokio/additional_dependencies.toml" >> Cargo.toml
	case "--leptos"
		cp -r $FILE_SNIPPETS_PATH/$lang/presets/leptos/* ./
		cat ./additional_dependencies.toml >> Cargo.toml || :
		rm -r additional_dependencies.toml || :
	case "*"
		cp -r "$FILE_SNIPPETS_PATH/$lang/presets/default/src" src
	end
	touch src/lib.rs

	shared_after $argv[1] $lang
end

function pyn
	mkdir "$argv[1]"
	set lang "py"
	shared_before $argv[1] $lang

	cp -r "$FILE_SNIPPETS_PATH/$lang/presets/default"/* ./
	chmod u+x ./main.py

	shared_after $argv[1] $lang
end

#TODO: switch to flake.nix standard
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
	elan run --install nightly lake new "$argv"
	shared_before $argv[1]

	cp -f "$FILE_SNIPPETS_PATH/leanpkg.toml" ./leanpkg.toml
end

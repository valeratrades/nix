config_filepath="${HOME}/.config/PROJECT_NAME_PLACEHOLDER.toml"
config_dir="${HOME}/.config/PROJECT_NAME_PLACEHOLDER"
if [ -f "$config_filepath" ] || [ -d "$config_dir" ]; then
  echo "Copying project's toml config to examples/"
  mkdir -p ./examples

	if [ -f "$config_dir" ]; then
		cp -f "$config_filepath" ./examples/config.toml
	else
		[ -d ./examples/config ] || cp -r "$config_dir" ./examples/config
	fi

  git add examples/

  if [ $? -ne 0 ]; then
    echo "Failed to copy project's toml config to examples"
    exit 1
  fi
fi

if [ -f "Cargo.toml" ]; then
  cargo sort --workspace --grouped --order package,lints,dependencies,dev-dependencies,build-dependencies,features
	fd Cargo.toml --type f --exec git add {} \;
fi

# # Count LoC
tokei --output json > /tmp/tokei_output.json
LINES_OF_CODE=$(jq '.Total.code' /tmp/tokei_output.json )
BADGE_URL="https://img.shields.io/badge/LoC-${LINES_OF_CODE}-lightblue"
sed -i "s|!\[Lines Of Code\](.*)|![Lines Of Code](${BADGE_URL})|" README.md; git add README.md || :
#

rm commit >/dev/null 2>&1 # remove commit message text file if it exists
echo "Ran custom pre-commit hooks"


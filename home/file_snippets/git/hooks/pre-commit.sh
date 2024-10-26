#!/bin/sh

config_filepath="${HOME}/.config/PROJECT_NAME_PLACEHOLDER.toml"
if [ -f "$config_filepath" ]; then
  echo "Copying project's toml config to examples/"
  mkdir examples >/dev/null 2>&1
  cp -f $config_filepath ./examples/config.toml

  git add examples/

  if [ $? -ne 0 ]; then
    echo "Failed to copy project's toml config to examples"
    exit 1
  fi
fi

if [ -f "Cargo.toml" ]; then
  cargo sort --workspace
fi

# # Count LoC
tokei --output json > /tmp/tokei_output.json
LINES_OF_CODE=$(jq '.Total.code' /tmp/tokei_output.json )
BADGE_URL="https://img.shields.io/badge/LoC-${LINES_OF_CODE}-lightblue"
sed -i "s|!\[Lines Of Code\](.*)|![Lines Of Code](${BADGE_URL})|" README.md && git add README.md || :
#

rm commit >/dev/null 2>&1 # remove commit message text file if it exists

exit 0

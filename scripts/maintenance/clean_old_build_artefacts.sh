#!/bin/sh

directories="
	/home/v/tmp/
	/home/v/s/
	/home/v/g/
	/home/v/leetcode/
	/home/v/uni/
"


check_and_clean_cargo() {
	local dir=$1
	find "$dir" -name "Cargo.toml" | while read -r cargo_file; do
		parent_dir=$(dirname "$cargo_file")

		if [ -d "$parent_dir/target" ]; then
			last_change=$(stat -c %Y "$parent_dir")
			current_date=$(date +%s)
			diff=$((current_date - last_change))

			if [ "$diff" -gt $((4 * 7 * 24 * 3600)) ]; then
				echo "\033[32mCleaned build artefacts in: $parent_dir\033[0m"
				(cd "$parent_dir" && cargo clean)
			fi
		fi
	done
}

echo "\033[34mCleaning old build artefacts\033[0m"
# could split to run in parallel, but ~/s/ takes most of the time.
for repo in $directories; do
	echo "Searching for stale projects in: \033[34m${repo}\033[0m"
	if [ -d "$repo" ]; then
		check_and_clean_cargo "$repo"
	else
		echo "\033[31mDirectory ${repo} does not exist\033[0m"
	fi
done

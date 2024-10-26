#!/bin/sh
# File is sourced on `cs` into the project's root. Allows to define a set of project-specific commands and aliases.

upload_python_library() {
	version=$(python ${HOME}/s/help_scripts/bump_version.py $(pwd)/pyproject.toml $1) || { return 1; }

	rm -rf ./dist ./build
	python -m build
	twine upload ./dist/* -u __token__ -p $PYPI_KEY

	message="."
	if [ -n "$2" ]; then
		message="$@"
	fi
	git add -A && git commit -m "$message" && git tag "v${version}" && git push --follow-tags
}

alais ul="upload_python_library"

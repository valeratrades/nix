#!/usr/bin/env bash

gh repo list valeratrades --limit 1000 --json name -q '.[].name' | while read repo; do
    echo "Setting secret for $repo"
    gh secret set loc_gist_token --repo "valeratrades/$repo" --body "$GITHUB_LOC_GIST"
done

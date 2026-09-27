#!/usr/bin/env bash
# Free-plan orgs don't expose org secrets to private repos, so every repo gets its own copy.

for owner in valeratrades ev-invest Service-Arb; do
    gh repo list "$owner" --limit 1000 --json name -q '.[].name' | while read repo; do
        echo "Setting secret for $owner/$repo"
        gh secret set loc_gist_token --repo "$owner/$repo" --body "$GITHUB_LOC_GIST"
    done
done

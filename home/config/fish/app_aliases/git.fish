# all general git shorthands

#TODO!!: start assigning difficulty score to all entries. Default to NaN.
# Could do it through a label with say black-color. Probably a series of labels, simply named {[1-9],NaN}

alias gl="lazygit"

set -g GIT_SHARED_MAIN_BRANCHES master main release stg prod
alias g="git"

function gg
	set prefix ""
	if [ "$argv[1]" = "p" ] || [ "$argv[1]" = "-p" ] || [ "$argv[1]" = "--prefix" ]
		set prefix "$argv[2]: "
		set argv $argv[3..-1]
	end

	if [ "$argv[1]" = "t" ] || [ "$argv[1]" = "-t" ] || [ "$argv[1]" = "--tag" ]
		git tag -a "$argv[2]" -m "$argv[2]"
		set argv $argv[3..-1]
	end

	if [ "$argv[1]" = "r" ] || [ "$argv[1]" = "-r" ] || [ "$argv[1]" = "--release" ]
		git push origin master:release --force-with-lease
		set argv $argv[2..-1]
	end

	set message "_"
	if test -n "$argv"
		set message "$argv"
	end
	set message "$prefix$message"

	# doesn't work, but leaving for future squash functionality
	# set squash_if_needed=""
	# if test (git log -1 --pretty=format:%s) = "$message"
	#     set squash_if_needed '--squash HEAD~1'
	# end

	# repeat the commit to go around the pre-commit formatting hooks that are currently failing if requiring formatting (wtf)
	git add -A; git commit -m "$message" || git commit -am "$message"; git push --follow-tags; git push --tags # --follow-tags is inconsistent
end

alias ggf="gg -p feat"
alias ggx="gg -p fix"
alias ggc="gg -p chore"
alias ggh="gg -p hack"
alias ggs="gg -p style"
alias ggt="gg -p test"
alias ggr="gg -p refactor"
alias ggp="gg -p perf"
alias ggd="gg -p docs"
alias ggi="gg -p ci"
alias ggm="gg -p move"
alias ggn="gg -p nuke" # important to have this here, as it additionally promotes simplification whenever possible
alias ggw="gg -p wip"

alias gup="git commit -a --fixup (git rev-parse HEAD)"
alias gupp="gup && git push --follow-tags"

function gbl
	# get branches sorted by date, with HEAD, name, commit hash, subject and author
	git for-each-ref --sort=committerdate refs/heads/ --format='%(HEAD) %(color:yellow)%(refname:short)%(color:reset) - %(color:red)%(objectname:short)%(color:reset) - %(contents:subject) - %(authorname) (%(color:green)%(committerdate:relative)%(color:reset))'
end

function gd
	set branch_name $argv[1]
	git branch -d $branch_name
	git push origin --delete $branch_name
end

function gf
	# not sure why this is not default
	git fetch origin $argv[1]:$argv[1] && git checkout $argv[1]
end

function git_force_pull
	git fetch --all && git reset --hard origin/(git branch --show-current)
end

function grr
	# Git really reset
	# discards all changes, including untracked files
	git reset --hard HEAD; git clean -fd; git stash clear
end

# GitHub aliases
alias gi="gh issue create -b \"\" -t"
alias gil="gh issue list"

alias gia="gh issue edit --add-assignee"
alias giam="gh issue edit --add-assignee @me"
alias gial="gh issue edit --add-label"

function giem
	set issue $argv[1]
	set milestone $argv[2]
	gh issue edit $issue --milestone $milestone
end

alias gic="gh issue close -r completed"
alias gir="gh issue close -r \"not planned\"" # for "retract"
alias gix="gh issue delete --yes"

alias git_rate_limit 'curl -L -X GET -H "Accept: application/vnd.github+json" -H "Authorization: token $GITHUB_KEY" https://api.github.com/rate_limit'

alias eg 'git branch -D tmp/experiment; git cb tmp/experiment'

function gpf
	# force push, but refuse on main-ish ones
	set branch (git rev-parse --abbrev-ref HEAD)
	switch $branch
	case $GIT_SHARED_MAIN_BRANCHES
		echo "Refusing to force push $branch"
		return 1
	case '*'
		git push --force-with-lease --follow-tags $argv 
	end
end
function gpff
	# same af `gpf`, but actual force push,-  not even `--with-lease`
	set branch (git rev-parse --abbrev-ref HEAD)
	switch $branch
	case $GIT_SHARED_MAIN_BRANCHES
		echo "Refusing to force push $branch"
		return 1
	case '*'
		git push --force --follow-tags $argv 
	end
end

function gbd
	# git branch delete, but refuse on main-ish ones
	set target $argv[1]
	switch $target
	case $GIT_SHARED_MAIN_BRANCHES
		echo "Refusing to delete $target"
		return 1
	case '*'
		git branch -D $target
		git push origin --delete $target
	end
end


#TODO!: add all issues outside of milestones to the list _if no milestone is specified_
function gifm
	set milestone $argv[1]
	if test -z "$milestone"
		set milestone (gh api "repos/{owner}/{repo}/milestones" --jq 'sort_by(.title) | .[].title' | head -n 1)
		echo "INFO: No milestone specified, defaulting to the latest one ($milestone) + issues without a milestone"

		echo "Issues without milestones:"
		script -f -q /dev/null -c "gh issue list --milestone=none" | awk 'NR > 3'
		echo ""
	end
	echo "Issues in milestone $milestone:"
	script -f -q /dev/null -c "gh issue list --milestone=$milestone" | awk 'NR > 3'
	echo ""
	echo "Bug Issues (across milestones):"
	script -f -q /dev/null -c 'gh issue list --label=bug' | awk 'NR > 3'
end

function gifa
	script -f -q /dev/null -c 'gh issue list --assignee="@me"' | awk 'NR > 3'
end

function gml
	gh api repos/:owner/:repo/milestones --jq '.[] | select(.state=="open") | "\(.title): \(.description | split("\n")[0] | gsub("\r"; ""))"'
end

alias git_zip="rm -f ~/Downloads/last_git_zip.zip && git ls-files -o -c --exclude-standard | zip ~/Downloads/last_git_zip.zip -@"

function gco
	set initial_query ""
	if test -n "$argv[1]"
		if git checkout "$argv[1]" 2>/dev/null
			return 0
		else
			set initial_query "$argv[1]"
		end
	end

	git branch | sed 's/^\* //' | fzf --height=20% --reverse --info=inline --query="$initial_query" | xargs git checkout
end

function gc
	#ex: gc neovim/neovim . -c
	set result (cargo -Zscript -q (dirname (status --current-filename))/git_clone.rs $argv[1] $argv[2])
	if [ $status = 0 ]
		if begin
			[ (count $argv) -ge 3 ]
			and begin
				[ "$argv[3]" = "--cd" ]
				or [ "$argv[3]" = "-c" ]
			end
		end
			cd $result
		else
			echo $result
		end
	else
		echo $result
	end
	return $status
end


# would put a todo for rewriting, but I'm on nix, this may be irrelevant now
#rewrite correctly from .zsh source, this is not at all what it is supposed to be
# although, do I even need this now that I'm on nix?
#function gb
#	set gb_readme '''
#	#build from source helper
#	Does git clone into /tmp, and then tries to build until it works.
#
#	ex: build neovim/neovim
#
#	some repositories have shorthands, eg: `build nvim` would work.
#	'''
#	if test "$argv[1]" = "nvim"
#		set target "neovim/neovim"
#	else if test "$argv[1]" = "eww"
#		set target "elkowar/eww"
#	else if test "$argv[1]" = "-h" -o "$argv[1]" = "--help" -o "$argv[1]" = "help"
#		printf $gb_readme
#		return 0
#	else if test -z "$argv[1]"
#		printf $gb_readme
#		return 1
#	else
#		set target "$argv[1]"
#	end
#
#	set initial_dir (pwd)
#	set target_dir (gc "$target")
#	if test $status -ne 0
#		return 1
#	end
#	cd "$target_dir" || return 1
#
#	and command cmake -S . -B ./build && cd ./build && sudo make install
#	and cd $initial_dir && rm -rf $target_dir
#end

function protect_branch
	set repo $argv[1]
	set branch $argv[2]

	curl -X PUT -H "Authorization: token $GITHUB_KEY" \
	-H "Accept: application/vnd.github.v3+json" \
	https://api.github.com/repos/$GITHUB_NAME/$repo/branches/$branch/protection \
	-d '{
	"required_status_checks": {
	"strict": true,
	"contexts": []
	},
	"enforce_admins": true,
	"required_pull_request_reviews": null,
	"restrictions": null,
	"allow_auto_merge": true,
	"allow_force_pushes": true,
	"allow_deletions": true
	}'

	curl -L -X PATCH \
	-H "Accept: application/vnd.github+json" \
	-H "Authorization: Bearer $GITHUB_KEY" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	https://api.github.com/repos/$GITHUB_NAME/$repo \
	-d '{"allow_auto_merge":true}'
end

function init_labels
	set pname $argv[1]

	function gh_submit_label
		set code 0
		set -l pname $argv[1]
		set -l name $argv[2]
		set -l color $argv[3]
		set -l description $argv[4]

		#TODO: request through `script` so it's colorful
		set -l output (gh api repos/$GITHUB_NAME/$pname/labels \
		-f name="$name" \
		-f color="$color" \
		-f description="$description" 2>&1)
		
		if echo $output | grep -q "already_exists"
			echo "Label '$name' already exists, skipping..."
		else
			echo $output >&2
			if not echo $output | grep -q "error"
				echo "Successfully created: '$name'"
			else
				echo "ERROR: $output"
				set code 1
			end
		end
		return $code
	end

	gh_submit_label $pname "ci" "808080" "New test or benchmark"
	gh_submit_label $pname "chore" "0052CC" "Small non-imaginative task"
	gh_submit_label $pname "breaking" "000000" "Implementing should be postponed until next major version"
	gh_submit_label $pname "hack" "FF8C00" "Hacky feature" #Q: not sold on this one, I think it could be fully encapsulated with just `rewrite`
	gh_submit_label $pname "rewrite" "008672" "Code quality"

	# present by default {{{
	gh_submit_label $pname "enhancement" "a2eeef" "New feature or request"
	gh_submit_label $pname "bug" "d73a4a" "Something isn't working"
	gh_submit_label $pname "documentation" "0075ca" "Improvements or additions to documentation"
	gh_submit_label $pname "duplicate" "cfd3d7" "This issue or pull request already exists"
	gh_submit_label $pname "good first issue" "7057ff" "Good for newcomers"
	gh_submit_label $pname "help wanted" "008672" "Extra attention is needed"
	gh_submit_label $pname "invalid" "e4e669" "This doesn't seem right"
	gh_submit_label $pname "question" "d876e3" "Further information is requested"
	gh_submit_label $pname "wontfix" "ffffff" "This will not be worked on"
	#,}}}

	functions -e gh_submit_label
end

## git new repository
#TODO!!!!: figure out how to sync the base labels settings across all repos
function gn
	if [ "$argv[1]" = "-h" ] || [ "$argv[1]" = "--help" ] || [ "$argv[1]" = "help" ]
		printf """\
		#git create new repo
		arg1: repository name
		arg2: --private or --public

		ex: gn my_new_repo --private
		"""
		return 0
	end
	set repo_name $argv[1]
	if [ "$argv[1]" = "--private" ] || [ "$argv[1]" = "--public" ]
		set repo_name (basename (pwd))
	else
		set argv $argv[2..-1]
	end

	# before running, ensure we have all the necessary env vars
	if test -z "$GITHUB_NAME"
		echo "ERROR: GITHUB_NAME is not set"
		return 1
	end
	if test -z "$GITHUB_KEY"
		echo "ERROR: GITHUB_KEY is not set"
		return 1
	end
	if test -z "$GITHUB_LOC_GIST"
		echo "WARNING: GITHUB_LOC_GIST is not set, loc_gist_token secret will not be created // in my setup it's used for LoC badge generation"
	end

	git init
	git add .
	git commit -m "Initial Commit"
	gh repo create $repo_name $argv[1] --source=.
	git remote add origin https://github.com/$GITHUB_NAME/$repo_name.git
	git push -u origin master

	init_labels $repo_name

	curl -L -X POST \
	-H "Accept: application/vnd.github+json" \
	-H "Authorization: token $GITHUB_KEY" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	https://api.github.com/repos/$GITHUB_NAME/$repo_name/milestones \
	-d '{
	"title":"1.0",
	"state":"open",
	"description":"Minimum viable product"
	}'

	curl -L -X POST \
	-H "Accept: application/vnd.github+json" \
	-H "Authorization: token $GITHUB_KEY" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	https://api.github.com/repos/$GITHUB_NAME/$repo_name/milestones \
	-d '{
	"title":"2.0",
	"state":"open",
	"description":"Fix bugs, rewrite hacks"
	}'

	curl -L -X POST \
	-H "Accept: application/vnd.github+json" \
	-H "Authorization: token $GITHUB_KEY" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	https://api.github.com/repos/$GITHUB_NAME/$repo_name/milestones \
	-d '{
	"title":"3.0",
	"state":"open",
	"description":"More and better"
	}'

	if test -n "$GITHUB_LOC_GIST"
		echo "Setting loc_gist_token secret..."
		gh secret set loc_gist_token --repo "$GITHUB_NAME/$repo_name" --body "$GITHUB_LOC_GIST"
	end
end

#TODO: make a file in main .github repo to store all additional labels defined for all repositories. Than change the label-manipulation commands to simply overwrite those. (or check for differences first, but that's more difficult, as some can have eg same name but outdated description)
function git_add_global_label
	set label_name $argv[1]
	set label_description $argv[2]
	set label_color $argv[3]

	gh repo list $GITHUB_NAME --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' | rg -v '\.github$|'"$GITHUB_NAME"'$' | while read -l repo
		echo "Adding label to $repo"
		gh api repos/$repo/labels \
		-f name="$label_name" \
		-f color="$label_color" \
		-f description="$label_description"
	end
end

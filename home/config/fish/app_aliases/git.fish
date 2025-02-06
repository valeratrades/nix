# all general git shorthands

#TODO!!: start assigning difficulty score to all entries. Default to NaN.
# Could do it through a label with say black-color. Probably a series of labels, simply named {[1-9],NaN}

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
	git add -A; git commit -m "$message"; git commit -am "$message"; git push --follow-tags
end

alias ggf="gg -p feat"
alias ggx="gg -p fix"
alias ggc="gg -p chore"
alias ggs="gg -p style"
alias ggt="gg -p test"
alias ggr="gg -p refactor"
alias ggp="gg -p perf"
alias ggd="gg -p docs"
alias ggi="gg -p ci"

alias gup="git commit -a --fixup (git rev-parse HEAD) && git push --follow-tags"

function gd
	set branch_name $argv[1]
	git branch -d $branch_name
	git push origin --delete $branch_name
end

function git_pull_force
	git fetch --all && git reset --hard origin/(git branch --show-current)
end
alias git_force_pull="git_pull_force"

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
	set result (cargo -Zscript -q (dirname (status --current-filename))/git_clone.rs $argv)
	if [ $status = 0 ] && [ (count $argv) = 1 ]
		cd $result
	else
		echo $result
	end
	return $status
end

function gpr
	set current_branch (git branch --show-current)
	set target_branch $argv[1]
	# could ask whether I want to push
	yes | gh pr create -B "$target_branch" -f -t "$current_branch"
	git checkout $target_branch
	set pr_number (gh pr list --limit 100 --json number,title | jq -r --arg title "$current_branch" '.[] | select(.title == $title) | .number')
	yes | gh pr merge -dm "$pr_number"
end

#TODO: a thing to sync fork


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
	set repo_name $argv[1]
	gh api repos/$GITHUB_NAME/$repo_name/labels \
	-f name="ci" \
	-f color="808080" \
	-f description="New test or benchmark"

	gh api repos/$GITHUB_NAME/$repo_name/labels \
	-f name="chore" \
	-f color="0052CC" \
	-f description="Small non-imaginative task"

	gh api repos/$GITHUB_NAME/$repo_name/labels \
	-f name="breaking" \
	-f color="000000" \
	-f description="Implementing should be postponed until next major version"

	gh api repos/$GITHUB_NAME/$repo_name/labels \
	-f name="enhancement" \
	-f color="a2eeef" \
	-f description="New feature or request"
	#gh api -X DELETE repos/$GITHUB_NAME/$repo_name/labels/enhancement
end

## git new repository
#TODO!!!!!!: figure out how to sync the base labels settings across all repos
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

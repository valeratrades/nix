# all general git shorthands

#TODO!!: start assigning difficulty score to all entries. Default to NaN.
# Could do it through a label with say black-color. Probably a series of labels, simply named {[1-9],NaN}

alias g="git"

function gg
	set prefix ""
	if test "$argv[1]" = "p" -o "$argv[1]" = "-p" -o "$argv[1]" = "--prefix"
		set prefix "$argv[2]: "
		set argv $argv[3..-1]
	end

	if test "$argv[1]" = "t" -o "$argv[1]" = "-t" -o "$argv[1]" = "--tag"
		git tag -a "$argv[2]" -m "$argv[2]"
		set argv $argv[3..-1]
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
	git add -A; and git commit -m "$message"; and git push --follow-tags
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

alias ggup="gg 'fixup!'"

function gd
	set branch_name $argv[1]
	git branch -d $branch_name
	git push origin --delete $branch_name
end

function git_pull_force
	git fetch --all; and git reset --hard origin/(git branch --show-current)
end

# GitHub aliases
alias gi="gh issue create -b \"\" -t"
alias gil="gh issue list"
alias gic="gh issue close -r completed"
alias gia="gh issue edit --add-assignee"
alias giam="gh issue edit --add-assignee @me"
alias gila="gh issue edit --add-label"

function gifm
	set milestone $argv[1]
	if test -z "$milestone"
		set milestone (gh api "repos/{owner}/{repo}/milestones" --jq 'sort_by(.title) | .[].title' | head -n 1)
	end
	script -f -q /dev/null -c="gh issue list --milestone=$milestone" | awk 'NR > 3'
	script -f -q /dev/null -c='gh issue list --label=bug' | awk 'NR > 3'
end

function gifa
	script -f -q /dev/null -c='gh issue list --assignee="@me"' | awk 'NR > 3'
end

function gml
	gh api repos/:owner/:repo/milestones --jq '.[] | select(.state=="open") | "\(.title): \(.description | split("\n")[0] | gsub("\r"; ""))"'
end

alias gir="gh issue close -r \"not planned\""
alias gid="gh issue delete --yes"

alias git_zip="rm -f ~/Downloads/last_git_zip.zip; and git ls-files -o -c --exclude-standard | zip ~/Downloads/last_git_zip.zip -@"

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
	set help_message """\
	#git clone on rails.
	give repo name, it clones into /tmp or provided directory.

	ex: gc neovim/neovim
	"""
	if string match -q "://" "$argv[1]"
		set url "$argv[1]"
	else
		set url "https://github.com/$argv[1]"
	end

	if test "$argv[1]" = "-h" -o "$argv[1]" = "--help" -o "$argv[1]" = "help" -o (count $argv) = 0
		printf "$help_message"
		return 0
	end

	set filename (string split "/" $url | tail -n 1)
	set filename (string replace -r '\\.git$' '' $filename)
	if test (count $argv) = 1
		if test (pwd) = "/tmp/$filename"
	cd - &>/dev/null
	end
	rm -rf /tmp/$filename
	git clone --depth=1 "$url" "/tmp/$filename" 1>&2
	and cd "/tmp/$filename"; or return 1
	pwd
	else if test (count $argv) = 2
	set target $argv[2]
	if test -d "$argv[2]"
	set target "$argv[2]/$filename"
	end
	git clone --depth=1 "$url" "$target"; or return 1
	end
	end

	set gb_readme '''
	#build from source helper
	Does git clone into /tmp, and then tries to build until it works.

	ex: build neovim/neovim

	some repositories have shorthands, eg: `build nvim` would work.
	'''

	function gb
	if test "$argv[1]" = "nvim"
	set target "neovim/neovim"
	else if test "$argv[1]" = "eww"
	set target "elkowar/eww"
	else if test "$argv[1]" = "-h" -o "$argv[1]" = "--help" -o "$argv[1]" = "help"
	printf $gb_readme
return 0
else if test -z "$argv[1]"
printf $gb_readme
return 1
else
set target "$argv[1]"
end

set initial_dir (pwd)
set target_dir (gc "$target")
if test $status -ne 0
return 1
end
cd "$target_dir"; or return 1

and command cmake -S . -B ./build; and cd ./build; and sudo make install
and cd $initial_dir; and rm -rf $target_dir
end

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

function gn
if test "$argv[1]" = "-h" -o "$argv[1]" = "--help" -o "$argv[1]" = "help"
printf """\
#git create new repo
arg1: repository name
arg2: --private or --public

ex: gn my_new_repo --private
"""
return 0
end
set repo_name $argv[1]
if test "$argv[1]" = "--private" -o "$argv[1]" = "--public"
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

gh api repos/$GITHUB_NAME/$repo_name/labels \
-f name="ci" \
-f color="808080" \
-f description="New test or benchmark"

gh api -X DELETE repos/$GITHUB_NAME/$repo_name/labels/enhancement

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
end

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

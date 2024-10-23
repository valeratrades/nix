# all general git shorthands

#TODO!!: start assigning dififculty score to all entries. Default to NaN.
#Could do it through a label with say black-color. Probably a series of labels, simply named {[1-9],NaN}

alias g="git"
gg() {
	# needs to be processed first, or acceess aliases would have to be turned into functions
	prefix=""
	if [ "$1" = "p" ] || [ "$1" = "-p" ] || [ "$1" = "--prefix" ]; then
		prefix="${2}: "
		shift 2
	fi

	if [ "$1" = "t" ] || [ "$1" = "-t" ] || [ "$1" = "--tag" ]; then
		git tag -a "$2" -m "$2"
		shift 2
	fi


	message="_"
	if [ -n "$1" ]; then
		message="$*"
	fi
	message="${prefix}${message}"

	# squashes with the previous commit if the message is the same
	squash_if_needed=""
	# doesn't work
	#if [ "$(git log -1 --pretty=format:%s)" = ${message} ]; then
	#	squash_if_needed='--squash HEAD~1'
	#fi
	git add -A && git commit ${squash_if_needed} -m "${message}"; git push --follow-tags
}
alias ggf="gg -p feat"
alias ggx="gg -p fix"
alias ggc="gg -p chore"
alias ggs="gg -p style"
alias ggt="gg -p test"
alias ggr="gg -p refactor"
alias ggp="gg -p perf"
alias ggd="gg -p docs"
alias ggi="gg -p ci"

#TODO!!!!: a flag for generating the commit message from git diff with a (preferrably local) fast llm model.

alias ggup="gg 'fixup!'"

gd() {
	branch_name=${1}
	git branch -d ${branch_name}
	git push origin --delete ${branch_name}
}

git_pull_force() {
    git fetch --all && git reset --hard origin/$(git branch --show-current)
}

# # gh aliases
# Issue
alias gi="gh issue create -b \"\" -t"
alias gil="gh issue list"
alias gic="gh issue close -r completed"
alias gia="gh issue edit --add-assignee"
alias giam="gh issue edit --add-assignee @me"
alias gila="gh issue edit --add-label"

# Git Issues Filter Milestone (the closest one)
gifm() {
	if [ -n "$1" ]; then
		milestone="$1"
	else
		milestone=$(gh api "repos/{owner}/{repo}/milestones" --jq 'sort_by(.title) | .[].title' | head -n 1)
	fi
	# doesn't print the warnings because conditionals in piped commands are hard, so awk ends up cutting them off
	script -f -q /dev/null -c="gh issue list --milestone=${milestone}" | awk 'NR > 3'
	script -f -q /dev/null -c='gh issue list --label=bug' | awk 'NR > 3'
}
# Git Issues Filter Assignee (me)
gifa() {
	script -f -q /dev/null -c='gh issue list --assignee="@me"' | awk 'NR > 3'
}

gml() {
	gh api repos/:owner/:repo/milestones --jq '.[] | select(.state=="open") | "\(.title): \(.description | split("\n")[0] | gsub("\r"; ""))"'
}

# r for rejected
alias gir="gh issue close -r \"not planned\""
alias gid="gh issue delete --yes"
#

alias git_zip="rm -f ~/Downloads/last_git_zip.zip; git ls-files -o -c --exclude-standard | zip ~/Downloads/last_git_zip.zip -@"

gco() {
	if [ -n "$1" ]; then
		if git checkout "$1" 2>/dev/null; then
			return 0
		else
			initial_query="$1"
		fi
	else
		initial_query=""
	fi

	git branch | sed 's/^\* //' | 
		fzf --height=20% --reverse --info=inline --query="$initial_query" |
		xargs git checkout
}

#TODO!: make it default to my GITHUB_NAME, when no "/" are found in the provided repo query, and it's not in defaults.
gc() {
	help_message="""
#git clone on rails.
	give repo name, it clones into /tmp or provided directory.

  ex: gc neovim/neovim
"""
	if rg -q "://" <<< "$1"; then
		url="$1"
	else
		url="https://github.com/$1" 
	fi

	if [ "$#" = 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
		printf "$help_message"
		return 0
	fi

	filename=$(echo "${url}" | tr "/" "\n" | tail -n 1)
	filename="${filename%.git}"
	if [ "$#" = 1 ]; then
		if [ $(pwd) = "/tmp/${filename}" ]; then # otherwise will delete the directory under ourselves
			cd - &>/dev/null
		fi 
		rm -rf /tmp/${filename}
		git clone --depth=1 "$url" "/tmp/${filename}" 1>&2
		if [ $? -ne 0 ]; then
			return 1
		fi
		cd "/tmp/${filename}" || return 1
		pwd
	elif [ "$#" = 2 ]; then
		target="${2}"
		if [ -d "$2" ]; then
			target="${2%/}/${filename}"
		fi
		git clone --depth=1 "$url" "${target}"
		if [ $? -ne 0 ]; then
			return 1
		fi
	fi
}

gb_readme='''
#build from source helper
	Does git clone into /tmp, and then tries to build until it works.

	ex: build neovim/neovim

	some repositories have shorthands, eg: `build nvim` would work.
'''

gb() {
	if [ "$1" = "nvim" ]; then
		target="neovim/neovim"
	elif [ "$1" = "eww" ]; then
		target="elkowar/eww"
	elif [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
		printf ${gb_readme}
		return 0
	elif [ "$1" = "" ]; then
		printf ${gb_readme}
		return 1
	else
		target="$1"
	fi

	initial_dir=$(pwd)
	target_dir=$(gc "$target")
	if [ $? -ne 0 ]; then
		return 1
	fi
	cd "$target_dir" || return

	if printf "\n\033[34mtrying just cmake\033[0m\n" && make CMAKE_BUILD_TYPE=RelWithDebInfo && sudo make install; then
		:
	elif printf "\n\033[34mtrying -S .\033[0m\n" && cmake -S . -B ./build && cd ./build && sudo make install; then
		:
	elif printf "\n\033[34mtrying go build ./cmd/main.go and save to /usr/local/bin/\033[0m\n" && sudo go build -o /usr/local/bin/ ./cmd/main.go; then
		:
	elif printf "\n\033[34mtrying cargo install\033[0m\n" && cargo install -f --path . --root /usr/local/bin/; then
		:
	elif printf "\n\033[34mtrying cbi\033[0m\n" && cbi; then
		:
	elif printf "\n\033[34mtrying cb script\033[0m\n" && cb; then
		:
	elif printf "\n\033[34mtrying makepkg\033[0m\n" && makepkg -si; then
		:
	elif printf "\n\033[34mtrying meson\033[0m\n" && meson build && ninja -C build && sudo ninja -C build install; then
		:
	elif printf "\n\033[34mfuck this, asking chat gpt\033[0m\n" && ~/s/help_scripts/gpt_build.py "${target_dir}"; then
		:
	else
		return 1
	fi

	cd $initial_dir
	rm -rf $target_dir
}


#TODO!!!!: figure out actual NRSR enforcement on both push and pr merges.
protect_branch() {
	repo=${1}
	branch=${2}

	#TODO!!!!!: auto-include the contexts
	#NB: when edititing, careful not to add `,` after the last element - this is parsed as JSON
	curl -X PUT -H "Authorization: token ${GITHUB_KEY}" \
	-H "Accept: application/vnd.github.v3+json" \
	https://api.github.com/repos/${GITHUB_NAME}/${repo}/branches/${branch}/protection \
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
	#{
	#	"dismiss_stale_reviews": true,
	#	"require_code_owner_reviews": false,
	#	"required_approving_review_count": 0
	#},

	# allow auto-merge (not sure it is passed correctly higher up)
	curl -L \
	-X PATCH \
	-H "Accept: application/vnd.github+json" \
	-H "Authorization: Bearer ${GITHUB_KEY}" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	https://api.github.com/repos/${GITHUB_NAME}/${repo} \
	-d '{"allow_auto_merge":true}'
}


gn() {
	if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
		printf """\
#git create new repo
	arg1: repository name
	arg2: --private or --public

	ex: gn my_new_repo --private
"""
		return 0
	fi
	repo_name=${1}
	if [ "$1" = "--private" ] || [ "$1" = "--public" ]; then
		repo_name=$(basename $(pwd))
	else
		shift
	fi

	git init
	git add .
	git commit -m "Initial Commit"
	gh repo create ${repo_name} ${1} --source=.
	git remote add origin https://github.com/${GITHUB_NAME}/${repo_name}.git
	git push -u origin master
	#TODO!: also push and protect release if it exists
	#protect_branch ${repo_name} master

	# # Labels
	gh api repos/${GITHUB_NAME}/${repo_name}/labels \
		-f name="ci" \
		-f color="808080" \
		-f description="New test or benchmark"

	gh api \
  -X DELETE \
  repos/${GITHUB_NAME}/${repo_name}/labels/enhancement
	#

	curl -L -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: token ${GITHUB_KEY}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/${GITHUB_NAME}/${repo_name}/milestones \
  -d '{
		"title":"1.0",
		"state":"open",
		"description":"Minimum viable product"
	}'
	#TODO: create 4 more milestones. I think that far they could be standardized.
}

#DEPRECATED
gtpr() {
	commit_sha=$(curl -H "Authorization: token ${GITHUB_KEY}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${GITHUB_NAME}/${REPO}/commits?sha=${BRANCH}&per_page=1" | jq -r '.[0].sha')

	git branch -D temp-branch &>/dev/null 2>&1
	git push origin --delete temp-branch &>/dev/null 2>&1

	git checkout -b temp-branch
	git push origin temp-branch

	gg "$@"
	gh pr create --title "_" --body "" --base master --head temp-branch
	gh pr merge --auto --squash --delete-branch
}

#NB: careful! I don't know how to unroll yet
#TODO: figure out how to synchronize the labels in a chosen repo with all the other repos
git_add_global_label() {
	label_name=${1}
	label_description=${2}
	label_color=${3}

	repos=$(gh repo list ${GITHUB_NAME} --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' | rg -v '\.github$|'"${GITHUB_NAME}"'$')

	echo "$repos" | while IFS= read -r repo; do
		echo "Adding label to $repo"
		gh api repos/$repo/labels \
			-f name="${label_name}" \
			-f color="${label_color}" \
			-f description="${label_description}"
	done
}

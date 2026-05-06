#!/usr/bin/env fish
# Integration tests for git_scripts.rs push auto-force-with-lease detection.
# Each scenario builds a fresh bare-remote + local clone, mutates state, then
# invokes `git_scripts.rs push --dry-run` and asserts on the decision.

set script_dir (dirname (status --current-filename))
set gp $script_dir/git_scripts.rs

set fail 0
set pass 0

function fresh_repo
    set -g tmpdir (mktemp -d -t git_scripts_test.XXXXXX)
    git init --bare $tmpdir/remote.git -q -b master
    git -C $tmpdir clone -q ./remote.git local 2>/dev/null
    git -C $tmpdir/local config user.email test@test
    git -C $tmpdir/local config user.name test
    git -C $tmpdir/local config commit.gpgsign false
    git -C $tmpdir/local config tag.gpgsign false
    # Initial synced commit on master.
    echo "line1" >$tmpdir/local/file.txt
    echo "line2" >>$tmpdir/local/file.txt
    echo "line3" >>$tmpdir/local/file.txt
    git -C $tmpdir/local add -A
    git -C $tmpdir/local commit -q -m "initial"
    git -C $tmpdir/local push -qu origin master
end

function teardown
    rm -rf $tmpdir
    set -e tmpdir
end

function run_dry_push
    cd $tmpdir/local
    $gp push --dry-run 2>&1
end

function assert_force --argument-names name output
    if string match -q '*auto-enabling force-with-lease*' -- $output
        and string match -q '*--force-with-lease*' -- $output
        echo "PASS: $name"
        set -g pass (math $pass + 1)
    else
        echo "FAIL: $name"
        echo "----- output -----"
        echo $output
        echo "------------------"
        set -g fail (math $fail + 1)
    end
end

function assert_no_force --argument-names name output
    if not string match -q '*--force*' -- $output
        echo "PASS: $name"
        set -g pass (math $pass + 1)
    else
        echo "FAIL: $name"
        echo "----- output -----"
        echo $output
        echo "------------------"
        set -g fail (math $fail + 1)
    end
end

# --- scenario 1: synced, then commit + fixup, autosquashed (overlapping line) ---
# This is the canonical gups bug. The fixup edits the SAME line C1 added, so
# blob OIDs differ between local C1' and remote C1, defeating checks 1-4.
fresh_repo
echo "added by C1 (typo)" >>$tmpdir/local/file.txt
git -C $tmpdir/local add -A
git -C $tmpdir/local commit -q -m "feat: add line"
git -C $tmpdir/local push -q
# fixup the typo on the same line
sed -i 's/typo/fixed/' $tmpdir/local/file.txt
git -C $tmpdir/local add -A
git -C $tmpdir/local commit -q --fixup HEAD
GIT_SEQUENCE_EDITOR=true git -C $tmpdir/local rebase -q -i --autosquash HEAD~2
set out (run_dry_push | string collect)
assert_force "synced + fixup squashed (overlapping line)" $out
teardown

# --- scenario 2: synced, then commit + fixup, autosquashed (non-overlapping) ---
# Sanity check: fixup edits a different region; the existing merge_would_be_clean
# check should already cover this, so it must keep working.
fresh_repo
echo "C1 line" >>$tmpdir/local/file.txt
git -C $tmpdir/local add -A
git -C $tmpdir/local commit -q -m "feat: add C1"
git -C $tmpdir/local push -q
echo "fixup line in different place" >$tmpdir/local/other.txt
git -C $tmpdir/local add -A
git -C $tmpdir/local commit -q --fixup HEAD
GIT_SEQUENCE_EDITOR=true git -C $tmpdir/local rebase -q -i --autosquash HEAD~2
set out (run_dry_push | string collect)
assert_force "synced + fixup squashed (non-overlapping)" $out
teardown

# --- scenario 3: synced, two stacked fixups, both autosquashed ---
fresh_repo
echo "C1 line typo1 typo2" >>$tmpdir/local/file.txt
git -C $tmpdir/local add -A
git -C $tmpdir/local commit -q -m "feat: stacked"
git -C $tmpdir/local push -q
sed -i 's/typo1/fixed1/' $tmpdir/local/file.txt
git -C $tmpdir/local add -A
git -C $tmpdir/local commit -q --fixup HEAD
sed -i 's/typo2/fixed2/' $tmpdir/local/file.txt
git -C $tmpdir/local add -A
git -C $tmpdir/local commit -q --fixup HEAD~1
GIT_SEQUENCE_EDITOR=true git -C $tmpdir/local rebase -q -i --autosquash HEAD~3
set out (run_dry_push | string collect)
assert_force "synced + two fixups squashed" $out
teardown

# --- scenario 4: synced, fixups NOT squashed (still on top of remote) ---
# Local is a strict descendant of remote → fast-forward, no force needed.
fresh_repo
echo "C1 typo" >>$tmpdir/local/file.txt
git -C $tmpdir/local add -A
git -C $tmpdir/local commit -q -m "feat: x"
git -C $tmpdir/local push -q
sed -i 's/typo/fixed/' $tmpdir/local/file.txt
git -C $tmpdir/local add -A
git -C $tmpdir/local commit -q --fixup HEAD
sed -i 's/fixed/done/' $tmpdir/local/file.txt
git -C $tmpdir/local add -A
git -C $tmpdir/local commit -q --fixup HEAD
set out (run_dry_push | string collect)
assert_no_force "synced + fixups not squashed (fast-forward)" $out
teardown

# --- scenario 5: divergent commit, conflicting changes, mismatched subject ---
# Local and remote both modify the same line of file.txt differently, with
# unrelated subjects. 3-way merge should conflict; our subject check must NOT
# subsume this — otherwise force-with-lease would clobber remote work.
fresh_repo
sed -i 's/line2/line2 from remote/' $tmpdir/local/file.txt
git -C $tmpdir/local add -A
git -C $tmpdir/local commit -q -m "feat: remote edit"
git -C $tmpdir/local push -q
git -C $tmpdir/local reset --hard HEAD~1 -q
sed -i 's/line2/line2 from local/' $tmpdir/local/file.txt
git -C $tmpdir/local add -A
git -C $tmpdir/local commit -q -m "feat: local edit"
set out (run_dry_push | string collect)
assert_no_force "divergent conflicting edit, different subjects" $out
teardown

echo
echo "==> $pass passed, $fail failed"
exit $fail

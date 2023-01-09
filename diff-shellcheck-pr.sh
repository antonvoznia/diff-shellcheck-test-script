#!/bin/bash


getopts 'c:p:' opt

pr_number="${OPTARG}"

BASE_URL="https://github.com/rear/rear/pull/"
FILE_PR="$pr_number.patch"
FILE_DIFF_SHELLCHECK="enable-diff-shellcheck.patch"
WGET_URL="$BASE_URL/$pr_number/commits/"
GET_COMMIT_URL="https://github.com/rear/rear/commit"

MY_REAR_BRANCH="https://github.com/antonvoznia/rear.git"

ALL_SEVERITIES=("error" "warning" "info" "style")

git clone "$MY_REAR_BRANCH"
cd "rear"
cp "../$FILE_DIFF_SHELLCHECK" .

comment_str=""
commits=()
if [[ "${opt}" == "p" ]]; then
    wget "$WGET_URL"
    commits=($(cat index.html | grep -o "/rear/rear/pull/$pr_number/commits/[A-Za-z0-9]*" | uniq | xargs basename -a))
    comment_str="pr $pr_number"
elif [[ "${opt}" == "c" ]]; then
    commits=("$pr_number")
    comment_str="commit $pr_number"
else
    echo "Unknown flag: ${opt}"
    rm -rf rear
    exit 1
fi

commits_count=${#commits[@]}
commits_count=$(( commits_count - 1 ))


previous_hash=$(git rev-list --parents -n 1 "${commits[0]}" | awk '{print $2}')

for severity in ${ALL_SEVERITIES[*]}; do

    git checkout master

    sed -i "s/severity: .*/severity: $severity/" "$FILE_DIFF_SHELLCHECK"

    git checkout --force -b "reverse-severity-$severity-$pr_number-no-fix" ${commits[-1]}
    git apply -v --index "$FILE_DIFF_SHELLCHECK"
    git commit  -m "enable differential shellcheck"

    git checkout --force -b "reverse-severity-$severity-$pr_number-fix"
    rm -rf ".git/rebase-apply"
    counter=$commits_count
    while [[ counter -ge 0 ]]; do
        curl "$GET_COMMIT_URL/${commits[$counter]}.patch" | git apply -R -v --index
        counter=$(( counter - 1 ))
    done
    git commit  -m "severity $severity, $pr_number"

    rm index.html "$pr_number.patch"

    git push --set-upstream origin "reverse-severity-$severity-$pr_number-fix"
    git push --set-upstream origin "reverse-severity-$severity-$pr_number-no-fix"
    full_comment="reverse, severity $severity, $comment_str"
    gh pr create -R antonvoznia/rear -B "reverse-severity-$severity-$pr_number-no-fix" --fill  --title "$full_comment"\
        --body "$full_comment"
done

for severity in ${ALL_SEVERITIES[*]}; do

    git checkout master

    sed -i "s/severity: .*/severity: $severity/" "$FILE_DIFF_SHELLCHECK"

    git checkout --force -b "severity-$severity-$pr_number-no-fix" "$previous_hash"
    git apply -v --index "$FILE_DIFF_SHELLCHECK"
    git commit  -m "enable differential shellcheck"

    git checkout --force -b "severity-$severity-$pr_number-fix"
    rm -rf ".git/rebase-apply"
    for i in ${commits[@]}; do
        curl "$GET_COMMIT_URL/$i.patch" | git apply -v --index
        # echo "$GET_COMMIT_URL/$i.patch"
    done
    git commit  -m "severity $severity, $pr_number"

    rm index.html "$pr_number.patch"

    git push --set-upstream origin "severity-$severity-$pr_number-fix"
    git push --set-upstream origin "severity-$severity-$pr_number-no-fix"
    full_comment="severity $severity, $comment_str"
    gh pr create -R antonvoznia/rear -B "severity-$severity-$pr_number-no-fix" --fill  --title "$full_comment"\
        --body "$full_comment"
done

cd .. && rm -rf rear

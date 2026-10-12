#!/usr/bin/env bash
# The project version lives in three files: pyproject.toml, uv.lock and
# src/redis_fastapi/__init__.py.  Both release workflows use this script.
#
#   version.sh get
#       Print the version.  Fail if the three files disagree.
#   version.sh pr BRANCH PART EXPECTED
#       If BRANCH on origin still holds EXPECTED, bump PART (patch, minor or
#       major) on top of it and open a pull request into BRANCH.  If BRANCH
#       holds another version, the bump already happened: do nothing.  A
#       re-run rebuilds the pull request from the latest BRANCH.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
init=src/redis_fastapi/__init__.py

get() {
  python3 - "$init" <<'EOF'
import re, sys, tomllib
init = sys.argv[1]
found = {
    "pyproject.toml": tomllib.load(open("pyproject.toml", "rb"))["project"]["version"],
    "uv.lock": next(p["version"] for p in tomllib.load(open("uv.lock", "rb"))["package"]
                    if p["name"] == "fastapi-redis-sdk"),
    init: re.search(r'^__version__ = "(.*)"$', open(init).read(), re.M).group(1),
}
if len(set(found.values())) != 1:
    sys.exit(f"The version files disagree: {found}")
print(found["pyproject.toml"])
EOF
}

bump() {
  uv version --bump "$1" --no-sync > /dev/null   # pyproject.toml and uv.lock
  python3 - "$init" "$(uv version --short)" <<'EOF'
import re, sys
path, version = sys.argv[1:]
text = open(path).read()
open(path, "w").write(re.sub(r'^__version__ = ".*"$', f'__version__ = "{version}"', text, count=1, flags=re.M))
EOF
  get
}

pr() {
  local base=$1 part=$2 expected=$3 current new branch
  git fetch -q origin "$base"
  git checkout -q --detach "origin/$base"
  current=$(get)
  if [[ "$current" != "$expected" ]]; then
    echo "$base already holds $current; nothing to bump."
    return
  fi

  new=$(bump "$part")
  branch="bump/$base-$new"
  git -c user.name="github-actions[bot]" \
      -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
      commit -qam "chore: bump $base to $new"
  git push -q --force origin "HEAD:refs/heads/$branch"

  if [[ -n "$(gh pr list --base "$base" --head "$branch" --state open --json number --jq '.[].number')" ]]; then
    echo "Updated the open pull request from $branch."
  else
    gh pr create --base "$base" --head "$branch" --title "chore: bump $base to $new" \
      --body "Sets the version on \`$base\` to \`$new\`, the version after \`$expected\`."
  fi
}

case "${1:-}" in
  get) get ;;
  pr) pr "$2" "$3" "$4" ;;
  *) echo "Usage: $0 get | pr BRANCH patch|minor|major EXPECTED" >&2; exit 2 ;;
esac

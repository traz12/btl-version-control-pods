#!/usr/bin/env bash
# The version of an environment is the newest git tag it carries: dev/v1.2.3.
#
# Tags are the truth. The VERSION file only says where an environment starts:
# the very first release of dev, test or prod takes that number as it is, and
# every release after that steps up from the newest tag.
set -euo pipefail

usage() {
  echo "usage: version.sh <dev|test|prod> <current|next> [major|minor|patch]" >&2
  exit 1
}

env="${1:-}"
action="${2:-}"
bump="${3:-patch}"
[[ -n "$env" && -n "$action" ]] || usage

case "$env" in
  dev|test|prod) ;;
  *) echo "'$env' is not an environment. Use dev, test or prod." >&2; exit 1 ;;
esac

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Highest tag wins, not the most recent one, so an out-of-order tag cannot
# push the next release backwards.
newest=$(git tag -l "${env}/v*" \
  | sed "s|^${env}/v||" \
  | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -V | tail -1 || true)

case "$action" in
  current)
    echo "${newest:-none}"
    exit 0
    ;;
  next) ;;
  *) usage ;;
esac

if [[ -z "$newest" ]]; then
  # Nothing released yet for this environment. It starts at the seed exactly -
  # a label cannot make the first release anything other than that number.
  tr -d '[:space:]' < "$here/VERSION"
  echo
  exit 0
fi

IFS=. read -r major minor patch <<< "$newest"
case "$bump" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
  *) echo "'$bump' is not a size. Use major, minor or patch." >&2; exit 1 ;;
esac

echo "${major}.${minor}.${patch}"

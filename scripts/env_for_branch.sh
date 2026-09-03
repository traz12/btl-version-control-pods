#!/usr/bin/env bash
# One place decides which branch belongs to which environment.
# Both workflows call this, so the mapping can never drift between them.
set -euo pipefail

branch="${1:?usage: env_for_branch.sh <branch-name>}"
branch="${branch#refs/heads/}"

case "$branch" in
  dev)  echo "dev"  ;;
  test) echo "test" ;;
  main) echo "prod" ;;
  *)
    echo "No environment is mapped to branch '$branch'. Use dev, test or main." >&2
    exit 1
    ;;
esac

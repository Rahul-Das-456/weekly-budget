#!/bin/zsh
# Commit everything in this repo, pull the other person's latest (rebase), then push.
# Uses your normal git login for github.com. Stops on conflicts. Never force-pushes.
# Usage: push_github.sh "Commit message"
set -e
ROOT="$(git -C "${0:A:h}" rev-parse --show-toplevel)"
cd $ROOT
git add -A
git diff --cached --quiet || git commit -qm "${1:-Update Weekly Budget}"
git pull -q --rebase origin main || { echo "Pull had conflicts. Stop and sort them out with the person; don't force-push."; exit 1; }
git push -q origin main
echo "Pushed $(git rev-parse --short HEAD) → https://github.com/Rahul-Das-456/weekly-budget"

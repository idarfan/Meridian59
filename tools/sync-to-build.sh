#!/usr/bin/env bash
# Sync kod source changes from this WSL git repo (source of truth) to the
# Windows build tree at /mnt/c/Meridian59-Build (a plain, non-git checkout
# where blakserv.exe actually runs). Windows-side nmake still needs to be
# run afterward to recompile with the Windows toolchain and instbof/instrsc
# the .bof/.rsc into run/server -- this script only copies source.
#
# Usage:
#   tools/sync-to-build.sh              # preview (dry run)
#   tools/sync-to-build.sh --apply      # actually copy
#   tools/sync-to-build.sh --apply origin/master   # diff against a different base ref

set -euo pipefail

REPO_ROOT="/home/idarfan/Meridian59"
BUILD_ROOT="/mnt/c/Meridian59-Build"
BASE_REF="origin/master"
APPLY=0

for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    *) BASE_REF="$arg" ;;
  esac
done

if [ ! -d "$BUILD_ROOT" ]; then
  echo "Build tree not found at $BUILD_ROOT" >&2
  exit 1
fi

cd "$REPO_ROOT"

mapfile -t FILES < <(git diff --name-only --diff-filter=ACMR "$BASE_REF"..HEAD -- kod/)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "No changed kod/ files between $BASE_REF and HEAD."
  exit 0
fi

echo "Changed files ($BASE_REF..HEAD):"
for f in "${FILES[@]}"; do
  echo "  $f"
done
echo

if [ "$APPLY" -eq 0 ]; then
  echo "Dry run only -- rerun with --apply to copy these into $BUILD_ROOT"
  exit 0
fi

for f in "${FILES[@]}"; do
  src="$REPO_ROOT/$f"
  dst="$BUILD_ROOT/$f"
  if [ ! -f "$src" ]; then
    echo "skip (missing locally): $f"
    continue
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  echo "copied: $f"
done

echo
echo "Done. Now on the Windows side: cd to $BUILD_ROOT and run nmake (from the"
echo "directory containing the changed .kod, or the top level) to recompile"
echo "and instbof/instrsc the result into run/server."

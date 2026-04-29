#!/usr/bin/env bash
# apply_patches.sh — apply Marian-local patches onto vendored submodules.
#
# For each directory under patches/ that mirrors a submodule path, reset the
# submodule to its recorded SHA and apply the patches in lex order via
# `git am --3way`. Idempotent: if every patch in the dir is already present
# at the tip of the submodule (matching subjects), nothing is done.
#
# Run after `git submodule update --init` (and any time you re-pull).

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

PATCHES_ROOT="patches"

if [ ! -d "$PATCHES_ROOT" ]; then
  echo "No $PATCHES_ROOT directory found; nothing to do."
  exit 0
fi

# Find every directory under patches/ that contains *.patch files.
mapfile -t patch_dirs < <(find "$PATCHES_ROOT" -mindepth 1 -type d \
  -exec sh -c 'ls "$1"/*.patch >/dev/null 2>&1' _ {} \; -print | sort)

if [ "${#patch_dirs[@]}" -eq 0 ]; then
  echo "No patches found under $PATCHES_ROOT/."
  exit 0
fi

rc=0
for pdir in "${patch_dirs[@]}"; do
  # Submodule path = patches/<submodule-rel-path> with the leading "patches/"
  # stripped. e.g. patches/ips/pulp_cva6 -> ips/pulp_cva6.
  sub="${pdir#"$PATCHES_ROOT"/}"

  if ! git submodule status --recursive "$sub" >/dev/null 2>&1; then
    echo "WARN: $sub is not a registered submodule; skipping $pdir/." >&2
    continue
  fi

  recorded_sha="$(git ls-tree HEAD "$sub" | awk '{print $3}')"
  if [ -z "$recorded_sha" ]; then
    echo "WARN: cannot resolve recorded SHA for $sub; skipping." >&2
    rc=1
    continue
  fi

  # Idempotency: if HEAD's commit subjects from recorded_sha..HEAD match the
  # subjects of patches in pdir (in order), assume already applied.
  applied_subjects="$(git -C "$sub" log --format=%s "$recorded_sha"..HEAD 2>/dev/null | tac || true)"
  patch_subjects="$(for p in "$pdir"/*.patch; do \
    awk '/^Subject: / { sub(/^Subject: ?(\[PATCH[^]]*\] )?/,""); print; exit }' "$p"; \
  done)"

  if [ -n "$applied_subjects" ] && [ "$applied_subjects" = "$patch_subjects" ]; then
    echo "[$sub] patches already applied; skipping."
    continue
  fi

  echo "[$sub] resetting to $recorded_sha and applying patches from $pdir/"
  git -C "$sub" reset --hard "$recorded_sha" >/dev/null
  git -C "$sub" clean -fd >/dev/null

  for p in "$pdir"/*.patch; do
    echo "[$sub]   apply $(basename "$p")"
    if ! git -C "$sub" am --3way --keep-cr <"$(realpath "$p")"; then
      echo "ERROR: failed to apply $p in $sub. Bailing." >&2
      git -C "$sub" am --abort 2>/dev/null || true
      rc=1
      break
    fi
  done
done

exit "$rc"

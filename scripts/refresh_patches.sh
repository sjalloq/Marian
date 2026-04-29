#!/usr/bin/env bash
# refresh_patches.sh — regenerate patches/<sub>/*.patch from local commits in
# vendored submodules.
#
# For each submodule whose HEAD is ahead of the SHA recorded in the parent,
# regenerate `patches/<submodule-path>/*.patch` from the new commits via
# `git format-patch <recorded-sha>..HEAD`. The submodule's own SHA pin in
# the parent is intentionally left unchanged — patches are the source of
# truth, not the SHA.
#
# Workflow:
#   1. cd ips/pulp_cva6 && <edit files> && git commit -m "..."
#   2. scripts/refresh_patches.sh
#   3. From parent: git add patches/ && git commit
#      (do NOT git add the submodule SHA bump)

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

PATCHES_ROOT="patches"

# Iterate every registered submodule, recurse into nested ones.
mapfile -t subs < <(git submodule --quiet foreach --recursive 'echo "$displaypath"' | sort)

rc=0
for sub in "${subs[@]}"; do
  recorded_sha="$(git ls-tree HEAD "$sub" 2>/dev/null | awk '{print $3}')"
  if [ -z "$recorded_sha" ]; then
    continue  # not a tracked submodule at this level
  fi

  head_sha="$(git -C "$sub" rev-parse HEAD)"
  pdir="$PATCHES_ROOT/$sub"

  if [ "$head_sha" = "$recorded_sha" ]; then
    # No local commits. If patches dir exists for this sub, leave it alone
    # (so we don't accidentally drop patches when the submodule is reset).
    continue
  fi

  # Verify recorded_sha is an ancestor of HEAD; otherwise the submodule has
  # diverged and format-patch would do something surprising.
  if ! git -C "$sub" merge-base --is-ancestor "$recorded_sha" "$head_sha"; then
    echo "ERROR: $sub HEAD ($head_sha) is not a descendant of recorded SHA ($recorded_sha)." >&2
    echo "       Rebase the submodule onto the recorded SHA before refreshing." >&2
    rc=1
    continue
  fi

  echo "[$sub] regenerating patches under $pdir/"
  mkdir -p "$pdir"
  rm -f "$pdir"/*.patch
  git -C "$sub" format-patch \
    --no-signature --no-stat \
    --output-directory "$(realpath "$pdir")" \
    "$recorded_sha"..HEAD >/dev/null
  ls -1 "$pdir"
done

exit "$rc"

# Marian-local patches against vendored submodules

This tree holds patches that Marian carries against unmodified upstream
submodules. The submodule SHAs in the parent repo intentionally point at
upstream commits; the diffs in this directory are the *only* record of
Marian-local changes. That keeps each patch in a form that's ready to send
upstream when we want to.

## Layout

```
patches/<submodule-path>/000N-<short-description>.patch
```

The path under `patches/` mirrors the submodule path. e.g. patches against
`ips/pulp_cva6/` live under `patches/ips/pulp_cva6/`.

Patch files are produced by `git format-patch`, so each one carries a
commit message you can send upstream verbatim.

## Workflow

### Apply patches (after a fresh clone or `git submodule update`)

```bash
git submodule update --init --recursive
./scripts/apply_patches.sh
```

`apply_patches.sh` resets each submodule that has a corresponding
`patches/<sub>/` directory back to its recorded SHA, then runs
`git am --3way` over the patch series in lex order. The script is
idempotent — re-running it after a successful apply is a no-op.

### Add or update a patch

1. Edit files inside the submodule normally.
2. Commit the change inside the submodule:
   ```bash
   cd ips/pulp_cva6
   git add -p
   git commit -m "explicit static mode decl in ariane.sv"
   cd ../..
   ```
3. Regenerate the patch files in this tree:
   ```bash
   ./scripts/refresh_patches.sh
   ```
4. Stage and commit the regenerated `patches/` files in the parent repo.
   **Do not** stage the submodule SHA bump — `patches/` is the source of
   truth, not the submodule's HEAD.
   ```bash
   git add patches/
   git restore --staged ips/pulp_cva6   # if it got staged
   git commit -m "patch: explicit static mode decl in cva6 ariane.sv"
   ```

### Drop a patch

1. `rm patches/<sub>/000N-*.patch`
2. `git -C ips/<sub> reset --hard <recorded-sha>` (or just re-run
   `apply_patches.sh` — it resets first).
3. Commit the patch removal in the parent.

### Upstream a patch

The `.patch` files are `git format-patch` output, so they're ready to send
upstream as-is via `git send-email patches/ips/pulp_cva6/0001-*.patch` or
attached to a PR.

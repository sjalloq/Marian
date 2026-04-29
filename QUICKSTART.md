# Marian Quickstart

End-to-end steps to go from a clean clone to a running `chip_sim` Verilator
simulation. Targets Linux with the `environment-modules` system; tested on
Rocky Linux 9 / WSL2. Adjust package commands for your distro.

## 1. System prerequisites

For building the RISC-V toolchain and running Verilator:

```bash
# Rocky / RHEL / Fedora
sudo dnf install \
    autoconf automake python3 gawk bison flex texinfo gperf libtool \
    patchutils bc gcc gcc-c++ make git cmake ninja-build \
    libmpc-devel mpfr-devel gmp-devel zlib-devel expat-devel glib2-devel
```

```bash
# Debian / Ubuntu
sudo apt install \
    autoconf automake autotools-dev curl python3 python3-pip libmpc-dev \
    libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf \
    libtool patchutils bc zlib1g-dev libexpat-dev ninja-build git cmake \
    libglib2.0-dev libslirp-dev
```

Verilator must be available on `$PATH` (`v5.030+` for `--hierarchical
--trace-fst`). If you use environment modules, e.g. `module load
verilator/v5.048`.

## 2. Clone and initialise submodules

```bash
git clone <marian-repo-url>
cd marian
make repository_init        # fetches submodules; skips heavy/unused ones
scripts/apply_patches.sh    # applies Marian-local patches to vendored IPs
```

`apply_patches.sh` is idempotent — re-running is safe. Re-run it any time
you re-pull the parent repo or update submodules, since
`make repository_init` can leave a submodule on its recorded SHA without
the local patch series on top.

## 3. Build the RISC-V GCC toolchain

The `sw/Makefile` hardcodes the upstream `riscv64-unknown-elf-` triple and
expects sysroot at `<prefix>/riscv64-unknown-elf/`. Distro packages
(`riscv64-elf-*` on Arch, `riscv64-unknown-elf-*` on Debian) generally
**do not** include the Zvk vector-crypto extensions Marian needs, so build
from source:

```bash
mkdir -p ~/build && cd ~/build
git clone --recursive --depth 1 --branch 2023.12.12 \
    https://github.com/riscv-collab/riscv-gnu-toolchain.git \
    riscv-gnu-toolchain-2023.12.12

cd riscv-gnu-toolchain-2023.12.12
./configure \
    --prefix=/opt/gcc/riscv/gnu-2023.12.12 \
    --with-arch=rv64gcvzvkng \
    --enable-multilib \
    --with-cmodel=medany

make -j$(nproc)             # 1-3 hours; 13GB sources, ~30GB build, ~1.5GB install
```

The configure flags come from `sw/README.md`:

- `--with-arch=rv64gcvzvkng` — Zvk vector-crypto support.
- `--with-cmodel=medany` — Marian's bootram lives at `0x8000_0000`.
- `--enable-multilib` — produce libs for multiple ABIs.

The `2023.12.12` tag matches the version mentioned as tested in
`sw/README.md`.

Adjust `--prefix` if you want a different install location; everything
below assumes `/opt/gcc/riscv/gnu-2023.12.12`.

## 4. Install the environment module

```bash
mkdir -p /opt/modulefiles/gcc/riscv
cat > /opt/modulefiles/gcc/riscv/gnu-2023.12.12 <<'EOF'
#%Module

set install_root /opt/gcc/riscv/gnu-2023.12.12

prepend-path PATH $install_root/bin
setenv RISCV_DIR_GCC $install_root

# Upstream riscv-collab/riscv-gnu-toolchain at tag 2023.12.12, gcc 13.2.0.
# Configured with: --with-arch=rv64gcvzvkng --enable-multilib --with-cmodel=medany
# (per sw/README.md — Zvk required for Marian's vector-crypto tests).
# Tool prefix: riscv64-unknown-elf-
EOF
```

Make sure `/opt/modulefiles` is on `$MODULEPATH`. Then:

```bash
module avail gcc/riscv
module load gcc/riscv/gnu-2023.12.12
riscv64-unknown-elf-gcc --version    # should report gcc 13.2.0
echo "$RISCV_DIR_GCC"                # /opt/gcc/riscv/gnu-2023.12.12
```

## 5. Build and run chip_sim

With the toolchain and Verilator modules loaded:

```bash
cd hw/top_marian/dv/verilator

make verilate                       # build the Verilator binary (one-off; slow)
make test                           # builds sw/src/hello_world/, runs it on the sim
```

The `test` target builds `sw/bin/hello_world_gcc.{elf,bin}` via the
top-level `sw/Makefile`, then runs the Verilator binary with
`--meminit=ram,…,bin`.

### Useful knobs

| Variable            | Default                   | Purpose                               |
| ------------------- | ------------------------- | ------------------------------------- |
| `TEST`              | `hello_world`             | test under `sw/src/<TEST>/`           |
| `WAVES`             | (off)                     | `1` = `--trace`; `<path>` = `--trace=<path>` (FST) |
| `TERM_AFTER_CYCLES` | `10000000`                | hard timeout                          |
| `SIM_ARGS`          | (empty)                   | extra flags passed to the sim binary  |

Examples:

```bash
make test TEST=vc_test1                          # different test
make test WAVES=1                                # enable FST trace -> sim.fst
make test WAVES=$(pwd)/waves.fst                 # custom path
gtkwave $BUILD_DIR/chip_sim_build/sim.fst        # view (or surfer)
```

`make help` from `hw/top_marian/dv/verilator/` lists everything available.

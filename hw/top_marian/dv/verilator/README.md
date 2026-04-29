# Marian chip_sim (Verilator)

Pure C++/Verilator simulation of the Marian top, mirroring the
OpenTitan `hw/top_*/dv/verilator/` flow. Replaces the SV testbench
under `verilator/` with a thin chip-sim wrapper plus the OpenTitan
`VerilatorSimCtrl` / `VerilatorMemUtil` harness.

The legacy `verilator/` and `vsim/` flows are unchanged and continue
to work.

## Differences from the legacy `verilator/` flow

| | legacy `verilator/` | this `chip_sim` flow |
|---|---|---|
| Top module | `marian_tb_verilator` (SV TB) | `chip_sim_tb` (thin SV shim) |
| `--timing` | required | not used |
| Reset / clock generation | SV `initial`/`always` with `#delay` | C++ `VerilatorSimCtrl::Run()` |
| Memory init | `$readmemh` + hierarchical force | DPI (`simutil_memload` / `simutil_set_mem`) |
| Image format | `.hex` (`$readmemh` format) | ELF, VMEM or binary (selected via `--meminit`) |
| Trace control | compile-time only | runtime `--trace` flag, SIGUSR1 toggle |
| Test program swap | requires re-verilation | re-run with new `--meminit=...` |

## Build

```bash
make -C hw/top_marian/dv/verilator verilate
```

Output goes to `build/chip_sim_build/Vchip_sim_tb`.

Variables you can override on the make line:

| Variable | Default | Notes |
|---|---|---|
| `NR_LANES` | `4` | Must match the SV `+define+NR_LANES`; bakes the bootram width into the C++ harness. |
| `VLEN` | `512` | RVV `VLEN`. |
| `L2_NUM_ROWS` | `65536` | Bootram depth in 128-bit words. |
| `CLK_PERIOD` | `13.333` | Forwarded to RTL parameters that consume it. |

## Run

The fast path — build the SW under `sw/src/$(TEST)/` and run it in one step:

```bash
make -C hw/top_marian/dv/verilator test TEST=hello_world
```

This invokes `sw/Makefile` to produce `sw/bin/$(TEST)_gcc.elf`, then runs
the chip_sim binary with `--meminit=ram,<elf>` and a default cycle timeout.
Defaults assume the Arch `riscv64-elf-gcc` package is installed at `/usr`;
override `RISCV_DIR_GCC`, `RISCV_GCC`, `RISCV_OBJDUMP` if your toolchain
lives elsewhere or uses a different prefix.

Lower-level targets:

```bash
# Build SW only
make -C hw/top_marian/dv/verilator sw TEST=hello_world

# Run with arbitrary args
make -C hw/top_marian/dv/verilator run \
  SIM_ARGS="--meminit=ram,sw/bin/hello_world_gcc.elf --term-after-cycles=10000000"
```

Or invoke the binary directly:

```bash
build/chip_sim_build/Vchip_sim_tb \
  --meminit=ram,sw/bin/hello_world_gcc.elf \
  --term-after-cycles=10000000
```

### Common CLI flags

Provided by `VerilatorSimCtrl` and `VerilatorMemUtil`:

- `--meminit=<name>,<file>[,<type>]` &nbsp; load file into named memory region.
  The only registered region is `ram` (the bootram). `type` is auto-detected
  from the path; explicit values are `elf`, `vmem`, `bin`.
- `--term-after-cycles=<N>` &nbsp; hard timeout in cycles. `0` disables.
- `--trace[=<file>]` &nbsp; enable VCD tracing (compile must include `--trace`).
- `-h` / `--help` &nbsp; show all supported flags.
- `kill -USR1 <pid>` &nbsp; toggle tracing on a running simulation.

## End-of-test detection

`marian_top` exposes a 64-bit `exit_s` signal driven by `ctrl_registers`
(bit 0 = done, bits 63:1 = exit code). `chip_sim_tb.sv` surfaces this on
its `chip_exit_o` port; `MarianTestStatusExt` (in
`hw/dv/verilator/cpp/`) polls it each cycle and calls
`simctrl.RequestStop(success)` for an orderly shutdown with statistics.

## Layout

```
hw/
├── dv/                                 # shared DV components
│   ├── sv/                             # (placeholder)
│   ├── verilator/cpp/                  # Marian-specific C++ extensions
│   │   └── marian_test_status_ext.{h,cc}
│   └── dpi/                            # (placeholder)
└── top_marian/
    ├── rtl/
    │   └── sram.sv                     # bootram override (wraps OT prim_ram_1p)
    └── dv/verilator/
        ├── chip_sim_tb.sv              # thin SV wrapper around marian_top
        ├── chip_sim_tb.cc              # C++ main (uses VerilatorSimCtrl)
        ├── chip_sim_tb.vlt             # verilator config (hier_block + lint_off)
        ├── chip_sim.f                  # filelist (paths relative to repo root)
        ├── Makefile
        └── README.md
```

The OpenTitan `simutil_verilator` and `memutil` C++ sources are pulled
in directly from `third_party/opentitan/hw/dv/verilator/` — no copies.

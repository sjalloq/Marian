######################################################################
# Marian chip_sim Verilator makefile
#
# Mirrors OpenTitan's hw/top_*/dv/verilator/ pattern. Builds a pure
# C++/Verilator simulation: no SV testbench, no --timing, runtime-
# selectable trace, ELF/VMEM loading via DPI through prim_util_memload.
#
# Coexists with the legacy verilator/ flow — neither modifies the
# other's build directory or source files.
######################################################################

.DEFAULT_GOAL := help

ifneq ($(words $(CURDIR)),1)
 $(error Unsupported: GNU Make cannot build in directories containing spaces, build elsewhere: '$(CURDIR)')
endif

# ---------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------
THIS_DIR    := $(realpath $(CURDIR))
MARIAN_ROOT := $(realpath $(THIS_DIR)/../../../..)
OT_ROOT     := $(MARIAN_ROOT)/ips/opentitan

BUILD_DIR      ?= $(MARIAN_ROOT)/build
CHIP_SIM_BUILD ?= $(BUILD_DIR)/chip_sim_build
VERIL_LOG      ?= $(CHIP_SIM_BUILD)/verilate.log

# ---------------------------------------------------------------------
# Verilator
# ---------------------------------------------------------------------
ifeq ($(VERILATOR_ROOT),)
VERILATOR := verilator
else
export VERILATOR_ROOT
VERILATOR := $(VERILATOR_ROOT)/bin/verilator
endif

TOP_MODULE := chip_sim_tb

# ---------------------------------------------------------------------
# Design parameters (must match the SV side)
# ---------------------------------------------------------------------
NR_LANES    ?= 4
VLEN        ?= 512
L2_NUM_ROWS ?= 65536
CLK_PERIOD  ?= 13.333

# ---------------------------------------------------------------------
# SV defines
# ---------------------------------------------------------------------
VERIL_DEFINES := \
  +define+L2_INIT_METHOD=DPI \
  +define+L2_MEM_INIT_FILE= \
  +define+NR_LANES=$(NR_LANES) \
  +define+RVV_ARIANE=1 \
  +define+VLEN=$(VLEN) \
  +define+WT_DCACHE=1 \
  +define+VERILATOR=1 \
  +define+L2_NUM_ROWS=$(L2_NUM_ROWS) \
  +define+SIM_UART=1 \
  +define+CLK_PERIOD=$(CLK_PERIOD)

VERIL_INCLUDES := \
  +incdir+ips/pulp_apb/include/ \
  +incdir+ips/bow_common_ips/ips/axi/include/ \
  +incdir+ips/bow_common_ips/ips/pulp-common-cells/include/ \
  +incdir+ips/pulp_ara/hardware/include/ \
  +incdir+ips/pulp_reg_if/include/ \
  +incdir+ips/opentitan/hw/ip/prim/rtl/ \
  +incdir+ips/opentitan/hw/ip/prim_generic/rtl/

VERIL_WARN_SUPPRESS := \
  -Wno-BLKANDNBLK -Wno-CASEINCOMPLETE -Wno-CMPCONST -Wno-LATCH \
  -Wno-LITENDIAN -Wno-UNOPTFLAT -Wno-UNPACKED -Wno-UNSIGNED \
  -Wno-WIDTH -Wno-WIDTHCONCAT -Wno-ENUMVALUE -Wno-COMBDLY \
  -Wno-TIMESCALEMOD

# ---------------------------------------------------------------------
# C++ flags (forwarded to gcc by verilator's --build)
#
# - TOPLEVEL_NAME: required by verilated_toplevel.h.
# - L2_NUM_ROWS / NR_LANES: bake into the C++ harness so the MemArea
#   size matches the SV bootram parameters.
# - VL_USER_STOP: route $stop / $error through VerilatorSimCtrl::vl_stop.
# - Include paths for OT simutil/memutil and the local Marian extension.
# ---------------------------------------------------------------------
CXX_DEFINES := \
  -DTOPLEVEL_NAME=$(TOP_MODULE) \
  -DL2_NUM_ROWS=$(L2_NUM_ROWS) \
  -DNR_LANES=$(NR_LANES) \
  -DVL_USER_STOP=1 \
  -DVM_TRACE_FMT_FST=1

CXX_INCLUDES := \
  -I$(MARIAN_ROOT)/hw/dv/verilator/cpp \
  -I$(OT_ROOT)/hw/dv/verilator/cpp \
  -I$(OT_ROOT)/hw/dv/verilator/simutil_verilator/cpp

CXX_FLAGS := -O2 $(CXX_DEFINES) $(CXX_INCLUDES)
LD_FLAGS  := -lelf

# C++ harness sources. Use absolute paths — verilator's generated Makefile
# runs from $(CHIP_SIM_BUILD), not from $(MARIAN_ROOT), so relative paths in
# the filelist do not resolve.
CXX_SRCS := \
  $(MARIAN_ROOT)/hw/top_marian/dv/verilator/chip_sim_tb.cc \
  $(MARIAN_ROOT)/hw/dv/verilator/cpp/marian_test_status_ext.cc \
  $(OT_ROOT)/hw/dv/verilator/simutil_verilator/cpp/verilator_sim_ctrl.cc \
  $(OT_ROOT)/hw/dv/verilator/simutil_verilator/cpp/verilated_toplevel.cc \
  $(OT_ROOT)/hw/dv/verilator/cpp/verilator_memutil.cc \
  $(OT_ROOT)/hw/dv/verilator/cpp/dpi_memutil.cc \
  $(OT_ROOT)/hw/dv/verilator/cpp/mem_area.cc \
  $(OT_ROOT)/hw/dv/verilator/cpp/sv_scoped.cc
# NB: ecc32_mem_area.cc and scrambled_ecc32_mem_area.cc are not built — they
# pull in OT's secded_enc.{h,c} ECC support which Marian's plain bootram
# doesn't need. Add them back if you ever register an ECC-protected MemArea.

# ---------------------------------------------------------------------
# Verilator command line
# ---------------------------------------------------------------------
# --hierarchical + --trace-fst requires modern Verilator (verilator/verilator
# #6246 fixed before v5.030). The chip_sim flow uses v5.048 from /opt/modulefiles.
# v5.008 will segfault at runtime through Vlane_e::trace if both are enabled.
VERIL_FLAGS := \
  -f hw/top_marian/dv/verilator/chip_sim.f \
  $(VERIL_DEFINES) \
  $(VERIL_INCLUDES) \
  $(VERIL_WARN_SUPPRESS) \
  -O3 \
  -sv \
  --trace-fst \
  --hierarchical \
  hw/top_marian/dv/verilator/chip_sim_tb.vlt \
  --cc --exe --build \
  $(CXX_SRCS) \
  --top-module $(TOP_MODULE) \
  --Mdir $(CHIP_SIM_BUILD) \
  -CFLAGS "$(CXX_FLAGS)" \
  -LDFLAGS "$(LD_FLAGS)" \
  -j 8

# ---------------------------------------------------------------------
# SW build (delegates to sw/Makefile)
#
# Assumes a `riscv64-unknown-elf-` toolchain on $PATH (e.g. via env
# module). RISCV_DIR_GCC must point at the toolchain prefix so sw/Makefile
# can locate <prefix>/riscv64-unknown-elf as --sysroot. Override
# RISCV_TOOLCHAIN_PREFIX (or any individual binary) for a non-standard
# triple.
# ---------------------------------------------------------------------
TEST                   ?= hello_world
RISCV_TOOLCHAIN_PREFIX ?= riscv64-unknown-elf-
RISCV_GCC              ?= $(RISCV_TOOLCHAIN_PREFIX)gcc
RISCV_OBJDUMP          ?= $(RISCV_TOOLCHAIN_PREFIX)objdump
RISCV_OBJCOPY          ?= $(RISCV_TOOLCHAIN_PREFIX)objcopy

SW_ELF            := $(MARIAN_ROOT)/sw/bin/$(TEST)_gcc.elf
SW_BIN            := $(MARIAN_ROOT)/sw/bin/$(TEST)_gcc.bin
SIM_BIN           := $(CHIP_SIM_BUILD)/V$(TOP_MODULE)

TERM_AFTER_CYCLES ?= 10000000

# WAVES enables FST tracing at runtime. Empty (default) = off.
# WAVES=1 → --trace (default filename); WAVES=<path> → --trace=<path>.
WAVES ?=
ifeq ($(WAVES),)
TRACE_ARG :=
else ifeq ($(WAVES),1)
TRACE_ARG := --trace
else
TRACE_ARG := --trace=$(WAVES)
endif

SIM_ARGS ?=

# ---------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------
.PHONY: all verilate sw test clean help

all: verilate

verilate: | $(CHIP_SIM_BUILD)
	cd $(MARIAN_ROOT) && $(VERILATOR) $(VERIL_FLAGS) 2>&1 | tee $(VERIL_LOG)

# Build the test program with the existing sw/Makefile, then objcopy the ELF
# to a flat binary. We use the binary form for --meminit because OT's ELF
# loader is hardcoded to ELF32 (Ibex is RV32) and rejects Marian's ELF64
# output with "invalid binary class". TODO: extend dpi_memutil to dispatch
# on ELF class so we can load the ELF directly.
sw: $(SW_BIN)

$(SW_BIN): force-sw
	$(MAKE) -C $(MARIAN_ROOT)/sw compile_sw_gcc \
	  TEST=$(TEST) \
	  RISCV_DIR_GCC=$(RISCV_DIR_GCC) \
	  GCC_CC=$(RISCV_GCC) \
	  RISCV_OBJDUMP=$(RISCV_OBJDUMP)
	$(RISCV_OBJCOPY) -O binary $(SW_ELF) $(SW_BIN)

.PHONY: force-sw
force-sw:

# One-shot: build the SW for $(TEST), then run it on the chip_sim binary.
# Assumes `make verilate` has already been done (errors loudly if not).
test: sw
	@if [ ! -x $(SIM_BIN) ]; then \
	  echo "ERROR: $(SIM_BIN) not found. Run 'make verilate' first." >&2; \
	  exit 1; \
	fi
	cd $(CHIP_SIM_BUILD) && ./V$(TOP_MODULE) \
	  --meminit=ram,$(SW_BIN),bin \
	  --term-after-cycles=$(TERM_AFTER_CYCLES) \
	  $(TRACE_ARG) \
	  $(SIM_ARGS)

$(CHIP_SIM_BUILD):
	@mkdir -p $@

clean:
	@rm -rf $(CHIP_SIM_BUILD)

help:
	@echo "Targets:"
	@echo "  verilate   - build the chip_sim Verilator binary"
	@echo "  sw         - build sw/src/\$$(TEST)/ to sw/bin/\$$(TEST)_gcc.elf"
	@echo "  test       - sw + run on the chip_sim binary (TEST=hello_world by default)"
	@echo "  clean      - remove the chip_sim build directory"
	@echo ""
	@echo "SW build vars:"
	@echo "  TEST=<name>                  test under sw/src/<name>/  (default: hello_world)"
	@echo "  RISCV_DIR_GCC=<path>         toolchain install prefix   (must be set; provided by env module)"
	@echo "  RISCV_TOOLCHAIN_PREFIX=<p>   binary name prefix         (default: riscv64-unknown-elf-)"
	@echo "  RISCV_GCC=<path>             gcc binary                 (default: \$$(RISCV_TOOLCHAIN_PREFIX)gcc)"
	@echo "  RISCV_OBJDUMP=<path>         objdump binary             (default: \$$(RISCV_TOOLCHAIN_PREFIX)objdump)"
	@echo "  RISCV_OBJCOPY=<path>         objcopy binary             (default: \$$(RISCV_TOOLCHAIN_PREFIX)objcopy)"
	@echo ""
	@echo "Sim run vars:"
	@echo "  TERM_AFTER_CYCLES=<N>   hard timeout for 'test'    (default: 10000000)"
	@echo "  WAVES=1|<path>          enable FST tracing         (default: off; 1 = sim.fst, <path> = custom)"
	@echo "  SIM_ARGS=\"...\"          extra flags for 'test'"
	@echo ""
	@echo "Common SIM_ARGS:"
	@echo "  --meminit=ram,<file>          load ELF/VMEM into the bootram"
	@echo "  --term-after-cycles=<N>       hard timeout"
	@echo "  -h                            show simctrl built-in help"

// Copyright Shareef Jalloq
// Licensed under the Apache License, Version 2.0.
// SPDX-License-Identifier: Apache-2.0
//
// Verilator C++ harness for the Marian chip_sim flow. Mirrors the OpenTitan
// hw/top_*/dv/verilator/chip_sim_tb.cc pattern: the verilated top is wrapped
// by VerilatedToplevel, the simulation is driven by VerilatorSimCtrl, and
// memory loading is performed via VerilatorMemUtil + DPI (prim_util_memload).

#include <iostream>
#include <string>

#include "marian_test_status_ext.h"
#include "verilated_toplevel.h"
#include "verilator_memutil.h"
#include "verilator_sim_ctrl.h"

// L2_NUM_ROWS and NR_LANES are forwarded from the Makefile via -D so that the
// MemArea size matches the SV-side bootram parameters.
#ifndef L2_NUM_ROWS
#error "L2_NUM_ROWS must be defined to match the SV bootram depth."
#endif
#ifndef NR_LANES
#error "NR_LANES must be defined to compute the bootram word width."
#endif

// AxiDataWidth = (64 * NrLanes) / 2  (see marian_pkg.sv)
static constexpr uint32_t kBootramWidthBytes = (64u * NR_LANES) / 2u / 8u;
static constexpr uint32_t kBootramDepth      = L2_NUM_ROWS;
// marian_pkg::DRAMBase
static constexpr uint32_t kBootramBase       = 0x80000000u;

int main(int argc, char **argv) {
  chip_sim_tb top;
  VerilatorMemUtil memutil;
  VerilatorSimCtrl &simctrl = VerilatorSimCtrl::GetInstance();
  simctrl.SetTop(&top, &top.clk_i, &top.rst_ni,
                 VerilatorSimCtrlFlags::ResetPolarityNegative);

  // The bootram is the only memory the C++ harness needs to load. Its scope
  // is the prim_ram_1p instance inside hw/top_marian/rtl/sram.sv.
  const std::string bootram_scope(
      "TOP.chip_sim_tb.u_dut.i_bootram.i_prim_ram_1p");
  MemArea bootram(bootram_scope, kBootramDepth, kBootramWidthBytes);
  memutil.RegisterMemoryArea("ram", kBootramBase, &bootram);
  simctrl.RegisterExtension(&memutil);

  // End-of-test detection: poll chip_exit_o each cycle.
  MarianTestStatusExt test_status(simctrl, top.chip_exit_o);
  simctrl.RegisterExtension(&test_status);

  // Hold the design in reset long enough for any synchronous reset chains in
  // the CVA6 / Ara hierarchy to settle. The legacy SV TB uses 50 cycles.
  simctrl.SetInitialResetDelay(0);
  simctrl.SetResetDuration(50);

  std::cout << "Marian chip_sim (Verilator)\n"
            << "===========================\n"
            << "Bootram: depth=" << kBootramDepth
            << " width=" << (8u * kBootramWidthBytes) << "b"
            << " base=0x" << std::hex << kBootramBase << std::dec << "\n"
            << std::endl;

  return simctrl.Exec(argc, argv).first;
}

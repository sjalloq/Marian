// Copyright Shareef Jalloq
// Licensed under the Apache License, Version 2.0.
// SPDX-License-Identifier: Apache-2.0

#ifndef MARIAN_HW_DV_VERILATOR_CPP_MARIAN_TEST_STATUS_EXT_H_
#define MARIAN_HW_DV_VERILATOR_CPP_MARIAN_TEST_STATUS_EXT_H_

#include <cstdint>

#include "sim_ctrl_extension.h"
#include "verilator_sim_ctrl.h"

// SimCtrlExtension that polls the chip-level exit signal driven from
// marian_top.exit_s and requests an orderly simulation stop on completion.
//
// exit_signal layout (matches ctrl_registers.exit_o):
//   bit[0]    : test done
//   bits[63:1]: exit code (0 == pass)
class MarianTestStatusExt : public SimCtrlExtension {
 public:
  MarianTestStatusExt(VerilatorSimCtrl &ctrl, const uint64_t &exit_signal)
      : ctrl_(ctrl), exit_(exit_signal), done_(false) {}

  void OnClock(unsigned long sim_time) override;

 private:
  VerilatorSimCtrl &ctrl_;
  const uint64_t &exit_;
  bool done_;
};

#endif  // MARIAN_HW_DV_VERILATOR_CPP_MARIAN_TEST_STATUS_EXT_H_

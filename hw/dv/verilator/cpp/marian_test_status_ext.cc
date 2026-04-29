// Copyright Shareef Jalloq
// Licensed under the Apache License, Version 2.0.
// SPDX-License-Identifier: Apache-2.0

#include "marian_test_status_ext.h"

#include <iostream>

void MarianTestStatusExt::OnClock(unsigned long sim_time) {
  if (done_) return;
  if (!(exit_ & 1ull)) return;

  uint64_t code = exit_ >> 1;
  bool ok = (code == 0);

  std::cout << "[chip_sim] Test " << (ok ? "*** PASSED ***" : "*** FAILED ***")
            << " (tohost = " << code << ", time = " << sim_time << ")"
            << std::endl;

  done_ = true;
  ctrl_.RequestStop(ok);
}

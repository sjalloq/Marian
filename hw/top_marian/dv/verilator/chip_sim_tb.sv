//------------------------------------------------------------------------------
// Module   : chip_sim_tb
//
// Project  : Vector-Crypto Subsystem (Marian)
//
// Description: Verilator top-level for the chip_sim flow.
//
// Mirrors the OpenTitan hw/top_*/dv/verilator/chip_sim_tb.sv pattern: just
// clk_i and rst_ni ports, with the DUT instantiated and all unused chip
// I/O tied off internally. Reset, clock and trace control are all driven
// from the C++ harness (VerilatorSimCtrl). Memory loading is performed
// via DPI through prim_util_memload.svh (included by prim_ram_1p inside
// the bootram instance).
//
// The end-of-test signal exit_s lives inside marian_top; we surface it via
// a hierarchical reference so a SimCtrlExtension can poll it from C++.
//------------------------------------------------------------------------------

module chip_sim_tb
  import marian_pkg::*;
(
  input  logic        clk_i,
  input  logic        rst_ni,

  // End-of-test status. bit[0] = done, bits[63:1] = exit code.
  // Driven from u_dut.exit_s; consumed by the C++ test-status extension.
  output logic [63:0] chip_exit_o
);

  // -----------------------------------------------------------------
  // External AXI interfaces. ext_axi_m_req is driven by the boot-release
  // FSM below. ext_axi_s_resp is tied off ('0) — Marian's master AXI
  // port is unused in chip_sim and any outgoing transactions stall.
  // -----------------------------------------------------------------
  axi_external_m_req_t  ext_axi_m_req;
  axi_external_m_resp_t ext_axi_m_resp;
  axi_external_s_req_t  ext_axi_s_req;
  axi_external_s_resp_t ext_axi_s_resp;
  assign ext_axi_s_resp = '0;

  // -----------------------------------------------------------------
  // DUT
  // -----------------------------------------------------------------
  marian_top u_dut (
    .clk_i               ( clk_i           ),
    .rst_ni              ( rst_ni          ),

    .ext_axi_m_req_i     ( ext_axi_m_req   ),
    .ext_axi_m_resp_o    ( ext_axi_m_resp  ),
    .ext_axi_s_req_o     ( ext_axi_s_req   ),
    .ext_axi_s_resp_i    ( ext_axi_s_resp  ),

    .marian_gpio_i       ( '0              ),
    .marian_gpio_o       ( /* unused */    ),
    .marian_gpio_oe      ( /* unused */    ),

    .marian_ext_irq_i    ( 1'b0            ),
    .marian_ext_irq_o    ( /* unused */    ),

    .marian_qspi_data_i  ( '0              ),
    .marian_qspi_csn_o   ( /* unused */    ),
    .marian_qspi_data_o  ( /* unused */    ),
    .marian_qspi_oe      ( /* unused */    ),
    .marian_qspi_sclk_o  ( /* unused */    ),

    .marian_uart_rx_i    ( 1'b1            ),
    .marian_uart_tx_o    ( /* unused */    ),

    .marian_jtag_tck_i   ( 1'b0            ),
    .marian_jtag_tms_i   ( 1'b0            ),
    .marian_jtag_trstn_i ( 1'b1            ),
    .marian_jtag_tdi_i   ( 1'b0            ),
    .marian_jtag_tdo_o   ( /* unused */    )
  );

  // -----------------------------------------------------------------
  // Surface the DUT's end-of-test status. exit_s is declared inside
  // marian_top and assigned by ctrl_registers.exit_o.
  // -----------------------------------------------------------------
  assign chip_exit_o = u_dut.exit_s;

  // -----------------------------------------------------------------
  // Boot release: write 0x1 to ctrl_registers.bootram_rdy at 0x2030.
  //
  // CVA6 boots into the on-chip bootrom which polls bootram_rdy and
  // only jumps to the bootram once it's non-zero. The legacy SV TB
  // does this with #delay-driven AXI tasks; we replicate it here with
  // a clock-driven AXI-master FSM driving ext_axi_m_req. Memory has
  // already been preloaded by the C++ harness via DPI before clocks
  // start; we then wait a short time after reset before issuing the
  // boot-release write.
  // -----------------------------------------------------------------
  localparam logic [marian_pkg::AxiExtAddrWidth-1:0] BOOT_RELEASE_ADDR =
      marian_pkg::CTRLBase + 'h30;
  localparam logic [marian_pkg::AxiExtDataWidth-1:0] BOOT_RELEASE_DATA = 'h1;
  localparam int unsigned BOOT_RELEASE_DELAY_CYCLES = 16;

  typedef enum logic [2:0] {
    BOOT_S_WAIT,
    BOOT_S_AW,
    BOOT_S_W,
    BOOT_S_B,
    BOOT_S_DONE
  } boot_state_e;

  boot_state_e boot_state_q;
  logic [7:0]  boot_wait_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      boot_state_q <= BOOT_S_WAIT;
      boot_wait_q  <= '0;
    end else begin
      unique case (boot_state_q)
        BOOT_S_WAIT: begin
          if (boot_wait_q == BOOT_RELEASE_DELAY_CYCLES[7:0]) begin
            boot_state_q <= BOOT_S_AW;
          end else begin
            boot_wait_q <= boot_wait_q + 8'd1;
          end
        end
        BOOT_S_AW:   if (ext_axi_m_resp.aw_ready) boot_state_q <= BOOT_S_W;
        BOOT_S_W:    if (ext_axi_m_resp.w_ready)  boot_state_q <= BOOT_S_B;
        BOOT_S_B:    if (ext_axi_m_resp.b_valid)  boot_state_q <= BOOT_S_DONE;
        BOOT_S_DONE: /* idle */;
        default:     boot_state_q <= BOOT_S_DONE;
      endcase
    end
  end

  always_comb begin
    ext_axi_m_req = '0;
    unique case (boot_state_q)
      BOOT_S_AW: begin
        ext_axi_m_req.aw_valid = 1'b1;
        ext_axi_m_req.aw.addr  = BOOT_RELEASE_ADDR;
      end
      BOOT_S_W: begin
        ext_axi_m_req.w_valid = 1'b1;
        ext_axi_m_req.w.data  = BOOT_RELEASE_DATA;
        ext_axi_m_req.w.strb  = '1;
        ext_axi_m_req.w.last  = 1'b1;
      end
      BOOT_S_B: begin
        ext_axi_m_req.b_ready = 1'b1;
      end
      default: ;
    endcase
  end

endmodule

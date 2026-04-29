//------------------------------------------------------------------------------
// Module   : sram (chip_sim variant)
//
// Project  : Vector-Crypto Subsystem (Marian)
//
// Description: Single-port SRAM model for the Verilator chip_sim flow.
// Drop-in replacement for src/ip/marian/sram.sv: same module name, same
// parameters, same ports. Internally wraps OpenTitan's prim_ram_1p so the
// memory array can be loaded via the simutil_memload / simutil_set_mem DPI
// hooks provided by prim_util_memload.svh.
//
// The legacy src/ip/marian/sram.sv is retained for the original verilator/
// and vsim/ flows; the chip_sim filelist substitutes this file at compile
// time.
//------------------------------------------------------------------------------

module sram #(
  parameter int unsigned BYTE_WIDTH        = 8,
  parameter              INIT_FILE         = "",
  parameter int unsigned DATA_WIDTH        = 64,
  parameter int unsigned NUM_WORDS         = 1024,
  parameter bit          REGISTERED_OUTPUT = 0,

  localparam integer DataWidthBytes = (DATA_WIDTH + (BYTE_WIDTH-1)) / BYTE_WIDTH
)(
  input  logic                         clk_i,
  input  logic                         rst_ni,
  input  logic                         req_i,
  input  logic                         we_i,
  input  logic [$clog2(NUM_WORDS)-1:0] addr_i,
  input  logic [       DATA_WIDTH-1:0] wdata_i,
  input  logic [   DataWidthBytes-1:0] be_i,

  output logic [       DATA_WIDTH-1:0] rdata_o
);

  // prim_ram_1p requires Width % DataBitsPerMask == 0. The legacy sram.sv
  // accepts non-byte-aligned widths (e.g. CVA6 cache tag RAMs are 46/47 bits)
  // by rounding be_i up to the next byte. Pad the data path up to a multiple
  // of BYTE_WIDTH internally and trim on read.
  localparam int unsigned PaddedWidth = DataWidthBytes * BYTE_WIDTH;

  logic [PaddedWidth-1:0] wdata_padded;
  logic [PaddedWidth-1:0] wmask_padded;
  logic [PaddedWidth-1:0] rdata_padded;

  if (PaddedWidth > DATA_WIDTH) begin : gen_wdata_pad
    assign wdata_padded = {{(PaddedWidth-DATA_WIDTH){1'b0}}, wdata_i};
  end else begin : gen_wdata_nopad
    assign wdata_padded = wdata_i;
  end

  // Expand byte-enable into a PaddedWidth-wide bit-mask. prim_ram_1p collapses
  // each DataBitsPerMask-wide group back into a single mask bit.
  for (genvar i = 0; i < DataWidthBytes; i++) begin : gen_wmask
    assign wmask_padded[i*BYTE_WIDTH +: BYTE_WIDTH] = {BYTE_WIDTH{be_i[i]}};
  end

  logic [DATA_WIDTH-1:0] rdata_int;
  assign rdata_int = rdata_padded[DATA_WIDTH-1:0];

  prim_ram_1p #(
    .Width           ( PaddedWidth ),
    .Depth           ( NUM_WORDS   ),
    .DataBitsPerMask ( BYTE_WIDTH  ),
    .MemInitFile     ( INIT_FILE   )
  ) i_prim_ram_1p (
    .clk_i,
    .rst_ni,
    .req_i,
    .write_i  ( we_i         ),
    .addr_i,
    .wdata_i  ( wdata_padded ),
    .wmask_i  ( wmask_padded ),
    .rdata_o  ( rdata_padded ),
    .cfg_i    ( prim_ram_1p_pkg::RAM_1P_CFG_DEFAULT ),
    .cfg_rsp_o( /* unused */ )
  );

  if (REGISTERED_OUTPUT) begin : gen_output_reg
    logic [DATA_WIDTH-1:0] rdata_q;
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) rdata_q <= '0;
      else         rdata_q <= rdata_int;
    end
    assign rdata_o = rdata_q;
  end else begin : gen_no_output_reg
    assign rdata_o = rdata_int;
  end

endmodule

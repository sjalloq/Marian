//------------------------------------------------------------------------------
// Module   : idct4
//
// Project  : Vector-Crypto Subsystem (Marian) — AV1 transform extension
// Author(s): Shareef Jalloq
// Created  : 2026-04-30
//
// Description: AV1 4-point inverse DCT-II (1-D), as a Marian-style decoupled
// sub-unit. Mirrors the I/O shape of crypto_unit/aes.sv: takes one operand
// bundle, returns a 256-bit result.
//
// One invocation processes 4 rows of 4 elements each (16 SEW=16 elements
// total) in parallel. Math follows libaom's av1_idct4_new with cos_bit = 13:
//
//   stage 1 (reorder):   bf0[0]=in[0], bf0[1]=in[2], bf0[2]=in[1], bf0[3]=in[3]
//   stage 2 (half-btf):  bf1[0] = round_shift( cospi[32]*bf0[0] + cospi[32]*bf0[1] )
//                        bf1[1] = round_shift( cospi[32]*bf0[0] - cospi[32]*bf0[1] )
//                        bf1[2] = round_shift( cospi[48]*bf0[2] - cospi[16]*bf0[3] )
//                        bf1[3] = round_shift( cospi[16]*bf0[2] + cospi[48]*bf0[3] )
//   stage 3 (add/sub):   out[0] = bf1[0] + bf1[3]
//                        out[1] = bf1[1] + bf1[2]
//                        out[2] = bf1[1] - bf1[2]
//                        out[3] = bf1[0] - bf1[3]
//
// where cospi[N] = round(cos(pi*N/128) * 2^13). Constants below.
//
// Output is signed 16-bit per element. Caller is responsible for any further
// rounding/clipping required by the surrounding transform pass (e.g. final
// clip-to-bd at the residual path).
//
// 2-D 4x4 IDCT is achieved by SW issuing the instruction twice with a
// transpose between the two passes. A native 2-D variant can be added later.
//
// Inputs:
//  - crypto_args_buff_i: operand bundle from operand_collector. We only
//    consume vs2 (256 bits = 16 elements at SEW=16).
//  - pe_crypto_req_i   : decoded request; op == VAV1_IDCT4 selects this unit.
//
// Outputs:
//  - idct4_result_o    : 256-bit packed result (16 elements at SEW=16).
//
//------------------------------------------------------------------------------

module idct4
  import ara_pkg::*;
(
  input  operand_buff_t          crypto_args_buff_i,
  input  pe_crypto_req_t         pe_crypto_req_i,

  output logic [EGW256-1:0]      idct4_result_o
);

  // Mark req unused for now — kept in the interface for future SEW dispatch.
  /* verilator lint_off UNUSEDSIGNAL */
  pe_crypto_req_t unused_req;
  assign unused_req = pe_crypto_req_i;
  /* verilator lint_on UNUSEDSIGNAL */

  // ------------------------------------------------------------------
  // AV1 4-point IDCT cosines at cos_bit = 13 (mul by 2^13 = 8192)
  // ------------------------------------------------------------------
  localparam int unsigned COS_BIT  = 13;
  localparam logic signed [15:0] COSPI_16 = 16'sd7568; // round(cos( pi/8 ) * 8192)
  localparam logic signed [15:0] COSPI_32 = 16'sd5793; // round(cos( pi/4 ) * 8192)
  localparam logic signed [15:0] COSPI_48 = 16'sd3135; // round(cos(3pi/8 ) * 8192)
  localparam logic signed [31:0] ROUND    = 32'sd1 <<< (COS_BIT - 1);

  // ------------------------------------------------------------------
  // Unpack vs2 into 16 signed-16-bit elements
  // ------------------------------------------------------------------
  logic signed [15:0] in  [0:15];
  logic signed [15:0] out [0:15];

  for (genvar i = 0; i < 16; i++) begin : g_unpack
    assign in[i] = $signed(crypto_args_buff_i.vs2[i*16 +: 16]);
  end

  // ------------------------------------------------------------------
  // Per-row 1-D IDCT-II (4 rows × 4 elements)
  // ------------------------------------------------------------------
  for (genvar r = 0; r < 4; r++) begin : g_rows

    // Stage-1 reorder
    logic signed [15:0] s1_0, s1_1, s1_2, s1_3;
    assign s1_0 = in[r*4 + 0];
    assign s1_1 = in[r*4 + 2];
    assign s1_2 = in[r*4 + 1];
    assign s1_3 = in[r*4 + 3];

    // Stage-2 half-butterfly products (16 × 16 → 32-bit)
    logic signed [31:0] m_32_0, m_32_1, m_48_2, m_16_2, m_16_3, m_48_3;
    assign m_32_0 = COSPI_32 * s1_0;
    assign m_32_1 = COSPI_32 * s1_1;
    assign m_48_2 = COSPI_48 * s1_2;
    assign m_16_2 = COSPI_16 * s1_2;
    assign m_16_3 = COSPI_16 * s1_3;
    assign m_48_3 = COSPI_48 * s1_3;

    // Stage-2 sum-of-products with rounding-right-shift
    logic signed [31:0] s2_0_pre, s2_1_pre, s2_2_pre, s2_3_pre;
    logic signed [31:0] s2_0,     s2_1,     s2_2,     s2_3;

    assign s2_0_pre =  m_32_0 + m_32_1 + ROUND;
    assign s2_1_pre =  m_32_0 - m_32_1 + ROUND;
    assign s2_2_pre =  m_48_2 - m_16_3 + ROUND;
    assign s2_3_pre =  m_16_2 + m_48_3 + ROUND;

    assign s2_0 = s2_0_pre >>> COS_BIT;
    assign s2_1 = s2_1_pre >>> COS_BIT;
    assign s2_2 = s2_2_pre >>> COS_BIT;
    assign s2_3 = s2_3_pre >>> COS_BIT;

    // Stage-3 add/sub butterflies
    logic signed [31:0] s3_0, s3_1, s3_2, s3_3;
    assign s3_0 = s2_0 + s2_3;
    assign s3_1 = s2_1 + s2_2;
    assign s3_2 = s2_1 - s2_2;
    assign s3_3 = s2_0 - s2_3;

    // Truncate to 16-bit per-element output. Stage-range for AV1 4-point at
    // 8-bit profile is bd+8 = 16 bits (spec section 7.7.2 stage_range table),
    // so straight truncation is correct for the POC. A clamp to bd+8 can be
    // added if higher-bit-depth profiles are targeted.
    assign out[r*4 + 0] = s3_0[15:0];
    assign out[r*4 + 1] = s3_1[15:0];
    assign out[r*4 + 2] = s3_2[15:0];
    assign out[r*4 + 3] = s3_3[15:0];

  end : g_rows

  // ------------------------------------------------------------------
  // Pack 16 × 16-bit elements back into a 256-bit result
  // ------------------------------------------------------------------
  for (genvar i = 0; i < 16; i++) begin : g_pack
    assign idct4_result_o[i*16 +: 16] = out[i];
  end

endmodule

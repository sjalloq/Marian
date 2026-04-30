/*
 * File        : idct4_test.c
 * Test        : av1.idct4 — Marian-local custom-0 instruction
 * Author(s)   : Shareef Jalloq (riscv-rvv project)
 * Date        : 2026-04-30
 * Description : Drives av1.idct4 through the HW unit, compares against a
 *               libaom-derived C reference (av1_idct4_new at cos_bit=13).
 *
 *               Encoding: custom-0 (0x0B), funct6=000000, funct3=000,
 *                         vm=1 (unmasked).
 *
 *               Wire format (matches Marian's vcrypto_type accessors):
 *                 [funct6:6][vm:1][vs2:5][vs1:5][funct3:3][vd:5][opcode:7]
 *
 *               This v0 of the test pins vs2=v2, vd=v3, encoding raw via
 *               .4byte. A future revision can add a binutils patch for
 *               proper assembler support.
 */

#include <stdint.h>
#include <stddef.h>

#include "encoding.h"
#include "printf.h"
#include "runtime.h"

/* ------------------------------------------------------------------ */
/* C reference: AV1 4-point IDCT-II, cos_bit = 13                     */
/* (libaom av1_idct4_new — see aom/av1/common/av1_inv_txfm1d.c)       */
/* ------------------------------------------------------------------ */

#define COS_BIT     13
#define COSPI_16    7568   /* round(cos( pi/8 ) * 8192) */
#define COSPI_32    5793   /* round(cos( pi/4 ) * 8192) */
#define COSPI_48    3135   /* round(cos(3pi/8 ) * 8192) */

/* Round-shift right by COS_BIT, matching the rounding mode used in HW. */
static inline int32_t round_shift(int32_t v) {
  return (v + (1 << (COS_BIT - 1))) >> COS_BIT;
}

static void av1_idct4_ref(const int16_t *in, int16_t *out) {
  /* Stage 1: input reorder */
  int32_t bf0_0 = in[0];
  int32_t bf0_1 = in[2];
  int32_t bf0_2 = in[1];
  int32_t bf0_3 = in[3];

  /* Stage 2: half-butterfly products */
  int32_t bf1_0 = round_shift( COSPI_32 * bf0_0 +  COSPI_32 * bf0_1);
  int32_t bf1_1 = round_shift( COSPI_32 * bf0_0 + -COSPI_32 * bf0_1);
  int32_t bf1_2 = round_shift( COSPI_48 * bf0_2 + -COSPI_16 * bf0_3);
  int32_t bf1_3 = round_shift( COSPI_16 * bf0_2 +  COSPI_48 * bf0_3);

  /* Stage 3: add/sub butterflies; truncate to 16-bit */
  out[0] = (int16_t)(bf1_0 + bf1_3);
  out[1] = (int16_t)(bf1_1 + bf1_2);
  out[2] = (int16_t)(bf1_1 - bf1_2);
  out[3] = (int16_t)(bf1_0 - bf1_3);
}

/* ------------------------------------------------------------------ */
/* HW driver                                                          */
/* ------------------------------------------------------------------ */

/* av1.idct4 v3, v2  →  vd=3, vs2=2, vs1=0, vm=1, funct6=0, funct3=0
 *   bits[31:26]=funct6=0, bit[25]=vm=1, bits[24:20]=vs2=2,
 *   bits[19:15]=vs1=0,    bits[14:12]=funct3=0,
 *   bits[11:7]=vd=3,      bits[6:0]=opcode=0001011 (0x0B)
 *   ---------------------------------------------
 *   = 0x0220_018B
 */
#define AV1_IDCT4_V3_V2  ".4byte 0x0220018B"

/* SEW=16, LMUL=1, AVL=16 — one 4×4 block per call. */
static void run_hw_idct4(const int16_t *in16, int16_t *out16) {
  uint64_t vl;

  /* SEW=16, LMUL=1, AVL=16 */
  asm volatile ("vsetivli %0, 16, e16, m1, ta, ma" : "=r"(vl));

  /* Load 16 elements from in16 into v2 */
  asm volatile ("vle16.v v2, (%0)" :: "r"(in16) : "memory");

  /* Execute av1.idct4 v3, v2  (custom-0, funct6=0) */
  asm volatile (AV1_IDCT4_V3_V2);

  /* Store v3 to out16 */
  asm volatile ("vse16.v v3, (%0)" :: "r"(out16) : "memory");
}

/* ------------------------------------------------------------------ */
/* Test vectors and harness                                           */
/* ------------------------------------------------------------------ */

/* 16 input coefficients, four rows of four. Mix of values to exercise
 * sign-extension, rounding, and the butterfly sums.
 */
static const int16_t test_input[16] = {
  /* row 0 */    100,   50,    0,    0,
  /* row 1 */    256, -256,  128, -128,
  /* row 2 */     32,   32,   32,   32,
  /* row 3 */  -1000,  500, -250,  125,
};

int main(void) {
  int16_t hw_out[16];
  int16_t ref_out[16];
  uint32_t fail_count = 0;

  printf("\r\n********* AV1 IDCT4 TEST *********\r\n");

  /* Reference pass — process each row through the C model. */
  for (int r = 0; r < 4; r++) {
    av1_idct4_ref(&test_input[r * 4], &ref_out[r * 4]);
  }

  /* HW pass — single instruction over 16 elements. */
  run_hw_idct4(test_input, hw_out);

  /* Compare. */
  printf("\r\n%-4s %-8s %-8s %-8s %s\r\n",
         "idx", "in", "hw", "ref", "match");
  for (int i = 0; i < 16; i++) {
    int match = (hw_out[i] == ref_out[i]);
    if (!match) fail_count++;
    printf("%-4d %-8d %-8d %-8d %s\r\n",
           i, test_input[i], hw_out[i], ref_out[i],
           match ? "OK" : "FAIL");
  }

  if (fail_count == 0) {
    printf("\r\n*** av1.idct4 PASS *** (16/16 elements match reference)\r\n");
  } else {
    printf("\r\n*** av1.idct4 FAIL *** (%u/16 elements mismatch)\r\n",
           fail_count);
  }

  return (fail_count == 0) ? 0 : 1;
}

#include "fir595.h"

sample_t fir595(sample_t x) {
#pragma HLS INTERFACE mode=ap_ctrl_hs port=return
#pragma HLS INTERFACE mode=ap_none    port=x

    // Filter coefficients 0.2941, 0.6250, 0.2941 in Q15 (round(h * 2^15))
    const coef_t COEF[N_TAPS] = {9637, 20480, 9637};

    static sample_t shift_reg[N_TAPS] = {0, 0, 0};
#pragma HLS ARRAY_PARTITION variable=shift_reg type=complete  //this is so HLS doesnt use ram for this but makes shift registers

    // Shift old samples down, insert the new one
SHIFT:
    for (int i = N_TAPS - 1; i > 0; i--) {
#pragma HLS UNROLL
        shift_reg[i] = shift_reg[i - 1];
    }
    shift_reg[0] = x;

    // Multiply each sample by its coefficient and add them up
    acc_t acc = 0;
MAC:
    for (int i = 0; i < N_TAPS; i++) {
#pragma HLS UNROLL
        acc += shift_reg[i] * COEF[i];
    }

    // Undo the 2^15 coefficient scaling, with rounding (add 0.5 LSB, then shift)
    ap_int<33> y = ((ap_int<33>)acc + (1 << (COEF_SHIFT - 1))) >> COEF_SHIFT;

    // The DC gain is 1.2132, so loud low-frequency input overflows 16 bits: saturate
    if (y > 32767)       y = 32767;
    else if (y < -32768) y = -32768;

    return (sample_t)y;
}

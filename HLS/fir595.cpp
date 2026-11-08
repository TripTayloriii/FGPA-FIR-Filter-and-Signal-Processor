#include "fir595.h"

sample_t fir595(sample_t x) {
#pragma HLS INTERFACE mode=ap_ctrl_hs port=return
#pragma HLS INTERFACE mode=ap_none    port=x

    // Filter coefficients 0.5, -0.9922, 0.5 in Q7 (h * 2^7)
    const coef_t COEF[N_TAPS] = {64, -127, 64};

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
        acc += (acc_t)shift_reg[i] * COEF[i];
    }

    // Undo the 2^7 coefficient scaling, with rounding (add 0.5 LSB, then shift)
    ap_int<25> y = ((ap_int<25>)acc + (1 << (COEF_SHIFT - 1))) >> COEF_SHIFT;

    // Gain reaches 1.99 near 4 kHz, so loud treble overflows 16 bits: saturate
    if (y > 32767)       y = 32767;
    else if (y < -32768) y = -32768;

    return (sample_t)y;
}

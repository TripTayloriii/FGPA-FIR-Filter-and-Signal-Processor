#include "fir595.h"

sample_t fir595(sample_t x) {
#pragma HLS INTERFACE mode=ap_ctrl_hs port=return
#pragma HLS INTERFACE mode=ap_none    port=x

    // Filter coefficients: 5, 9, 5
    const coef_t COEF[N_TAPS] = {5, 9, 5};

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

    // Divide by 19 using multiply + shift, with rounding  becasue otherwsie teh amplitudes won't fit in 16bits
    prod_t scaled = (prod_t)acc * NORM_MULT;
    scaled += (prod_t)1 << (NORM_SHIFT - 1);   // add 0.5 LSB so the shift rounds
    prod_t y = scaled >> NORM_SHIFT;

    // make sure we still in 16bit range
    if (y > 32767)       y = 32767;
    else if (y < -32768) y = -32768;

    return (sample_t)y;
}
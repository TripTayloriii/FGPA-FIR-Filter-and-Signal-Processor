#ifndef FIR595_H
#define FIR595_H

#include <ap_int.h>

typedef ap_int<16> sample_t;   // signed 16-bit audio sample
typedef ap_int<5>  coef_t;     // coefficients 5 and 9 fit in 5 signed bits
typedef ap_int<21> acc_t;      // sum of products: 16 bits + growth from gain of 19
typedef ap_int<40> prod_t;     // accumulator * normalization constant

const int N_TAPS     = 3;
const int NORM_MULT  = 55188;  // round(2^20 / 19)
const int NORM_SHIFT = 20;

sample_t fir595(sample_t x);

#endif
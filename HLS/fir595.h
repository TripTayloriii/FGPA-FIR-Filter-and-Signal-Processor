#ifndef FIR595_H
#define FIR595_H

#include <ap_int.h>

// 3-tap low-pass FIR, fs = 8 kHz: h = {0.2941, 0.6250, 0.2941}
// (the module keeps its old name fir595 so the RTL around it doesn't change)

typedef ap_int<16> sample_t;   // signed 16-bit audio sample
typedef ap_int<16> coef_t;     // Q15 coefficients (9637 and 20480 fit in 16 signed bits)
typedef ap_int<32> acc_t;      // sum of products: max |acc| = 32768 * 39754 < 2^31

const int N_TAPS     = 3;
const int COEF_SHIFT = 15;     // coefficients are scaled by 2^15

sample_t fir595(sample_t x);

#endif

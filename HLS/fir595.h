#ifndef FIR595_H
#define FIR595_H

#include <ap_int.h>

// 3-tap high-pass FIR, fs = 8 kHz: h = {64, -127, 64} / 128 = {0.5, -0.9922, 0.5},
// followed by a x4 (+12 dB) output gain, so the net scaling is / 32
// (the module keeps its old name fir595 so the RTL around it doesn't change)

typedef ap_int<16> sample_t;   // signed 16-bit audio sample
typedef ap_int<8>  coef_t;     // Q7 coefficients (64 and -127 fit in 8 signed bits)
typedef ap_int<24> acc_t;      // sum of products: max |acc| = 32768 * 255 < 2^23

const int N_TAPS     = 3;
const int COEF_SHIFT = 5;      // /128 for the Q7 taps, x4 gain: net shift by 5

sample_t fir595(sample_t x);

#endif

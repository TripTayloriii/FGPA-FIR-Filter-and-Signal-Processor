"""Bit-accurate Python model of the HLS fir595 block (HLS/fir595.cpp).

Taps h = {0.2941, 0.6250, 0.2941} at fs = 8 kHz, stored in Q15:

    acc = 9637*x[n] + 20480*x[n-1] + 9637*x[n-2]   (exact integer)
    y   = (acc + 2**14) >> 15                       (arithmetic shift = floor)
    y   = clamp(y, -32768, 32767)                   (active: DC gain is 1.2132)

The delay line starts at zero, which is the state fir595 is in after reset.

Usage:
    python scripts/fir_model.py --gen-vectors sim/vectors
        writes stim.hex / expected.hex for the testbench (one 4-digit
        two's-complement hex sample per line)
"""
import argparse
import os

import numpy as np

COEF = (9637, 20480, 9637)   # round(h * 2^15) for h = 0.2941, 0.6250, 0.2941
COEF_SHIFT = 15


def fir595(x):
    """Filter an array of int16 samples, returns int16 samples (same length)."""
    x = np.asarray(x, dtype=np.int64)
    x1 = np.concatenate(([0], x[:-1]))          # x[n-1]
    x2 = np.concatenate(([0, 0], x[:-2]))[:len(x)]  # x[n-2]
    acc = COEF[0] * x + COEF[1] * x1 + COEF[2] * x2
    y = (acc + (1 << (COEF_SHIFT - 1))) >> COEF_SHIFT
    y = np.clip(y, -32768, 32767)
    return y.astype(np.int16)


def test_signal(fs=8000):
    """Short signal: impulses, full-scale extremes, a few sine tones, noise."""
    parts = []
    # impulse response: should come out as about 10000*[0.2941, 0.6250, 0.2941] then zeros
    parts.append(np.r_[10000, np.zeros(7)])
    # negative full-scale impulse and full-scale steps (checks the extremes;
    # the steps are amplified by 1.2132 and must saturate at -32768 / 32767)
    parts.append(np.r_[-32768, np.zeros(3)])
    parts.append(np.full(6, 32767))
    parts.append(np.full(6, -32768))
    # Nyquist-rate square wave (lowest gain of the filter: 0.0368)
    parts.append(np.tile([32767, -32768], 4))
    n = np.arange(64)
    for f in (300, 1000, 3000):
        parts.append(np.round(20000 * np.sin(2 * np.pi * f * n / fs)))
    # random samples: also leaves non-zero state in the delay line at the end,
    # so the testbench can tell whether reset really cleared it
    rng = np.random.default_rng(595)
    parts.append(rng.integers(-32768, 32768, 32))
    return np.concatenate(parts).astype(np.int16)


def write_hex(path, samples):
    with open(path, "w") as f:
        for s in samples:
            f.write(f"{int(s) & 0xFFFF:04x}\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--gen-vectors", metavar="DIR", required=True,
                    help="directory to write stim.hex / expected.hex into")
    args = ap.parse_args()

    os.makedirs(args.gen_vectors, exist_ok=True)
    stim = test_signal()
    expected = fir595(stim)
    write_hex(os.path.join(args.gen_vectors, "stim.hex"), stim)
    write_hex(os.path.join(args.gen_vectors, "expected.hex"), expected)
    print(f"Wrote {len(stim)} samples to {args.gen_vectors}")
    print("Impulse response (first 4):", expected[:4].tolist())


if __name__ == "__main__":
    main()

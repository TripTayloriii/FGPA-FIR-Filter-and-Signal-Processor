"""Stream a .wav file through the FPGA FIR filter and save the result.

    python scripts/send_wav.py "wavFiles/Trip Taylor.wav" --port COM5
    python scripts/send_wav.py in.wav --port COM5 --out filtered.wav --save-input in_8k.wav

Steps: read wav -> mono -> 8 kHz -> int16 -> UART (1 Mbaud, little-endian)
-> FPGA -> UART -> output.wav, then compare against fir_model.py.

Flow control: the FPGA returns exactly one sample per sample sent, a little
later. We never let more than WINDOW_SAMPLES be "in flight" (sent but not yet
received), so the FPGA's output FIFO (512 samples) can never overflow, even
if the PC is slow to read.
"""
import argparse
import math
import os
import sys
import time
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fir_model import fir595  # noqa: E402

FS_TARGET = 8000
WINDOW_SAMPLES = 256     # max samples in flight; keep <= FPGA FIFO_DEPTH
CHUNK_BYTES = 128        # bytes per write() call
RX_TIMEOUT_S = 2.0       # give up if nothing arrives for this long


def wav_to_pcm(wave_path):
    """Read a wav file, return (mono float samples on an int16 scale, sample rate)."""
    with wave.open(wave_path, "rb") as wav:
        num_channels = wav.getnchannels()
        width = wav.getsampwidth()
        fs = wav.getframerate()
        raw = wav.readframes(wav.getnframes())

    if width == 1:      # 8-bit wav is unsigned
        samples = (np.frombuffer(raw, dtype=np.uint8).astype(np.float64) - 128) * 256
    elif width == 2:
        samples = np.frombuffer(raw, dtype='<i2').astype(np.float64)
    elif width == 3:    # 24-bit: sign-extend 3 bytes into int32
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
        v = np.where(v & 0x800000, v - (1 << 24), v)
        samples = v.astype(np.float64) / 256
    elif width == 4:
        samples = np.frombuffer(raw, dtype='<i4').astype(np.float64) / 65536
    else:
        raise ValueError(f"Unsupported sample width: {width} bytes")

    samples = samples.reshape(-1, num_channels)
    mono_pcm = np.mean(samples, axis=1)  # collapse channels
    return mono_pcm, fs


def resample(x, fs_in, fs_out):
    if fs_in == fs_out:
        return x
    try:
        from scipy.signal import resample_poly
        g = math.gcd(fs_in, fs_out)
        return resample_poly(x, fs_out // g, fs_in // g)
    except ImportError:
        pass
    # numpy fallback: windowed-sinc low-pass below the new Nyquist, then
    # linear interpolation onto the new time grid
    if fs_out < fs_in:
        cutoff = 0.45 * fs_out / fs_in          # cycles/sample
        n = np.arange(-128, 129)
        h = 2 * cutoff * np.sinc(2 * cutoff * n) * np.blackman(len(n))
        x = np.convolve(x, h / h.sum(), mode="same")
    t_out = np.arange(int(len(x) * fs_out / fs_in)) * (fs_in / fs_out)
    return np.interp(t_out, np.arange(len(x)), x)


def to_int16(x):
    return np.clip(np.round(x), -32768, 32767).astype(np.int16)


def write_wav(path, samples, fs=FS_TARGET):
    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(fs)
        wav.writeframes(samples.astype('<i2').tobytes())


def stream_through_fpga(samples, port, baud):
    import serial  # needs pyserial (pip install pyserial)

    tx = samples.astype('<i2').tobytes()
    rx = bytearray()
    sent = 0
    window_bytes = 2 * WINDOW_SAMPLES

    with serial.Serial(port, baudrate=baud, timeout=0.01, write_timeout=2) as ser:
        input("Press the RESET button on the board, then press Enter here...")
        ser.reset_input_buffer()

        start = time.time()
        last_progress = time.time()
        last_print = 0.0
        while len(rx) < len(tx):
            # send while there is room in the window
            in_flight = sent - len(rx)
            if sent < len(tx) and in_flight < window_bytes:
                n = min(CHUNK_BYTES, len(tx) - sent, window_bytes - in_flight)
                ser.write(tx[sent:sent + n])
                sent += n

            # read whatever has come back (blocks for at most 10 ms)
            data = ser.read(max(1, ser.in_waiting))
            if data:
                rx += data
                last_progress = time.time()
            elif time.time() - last_progress > RX_TIMEOUT_S:
                print(f"\nTimeout: sent {sent} bytes, received {len(rx)} bytes.")
                break

            if time.time() - last_print > 0.5:
                print(f"\r{len(rx) // 2}/{len(samples)} samples", end="")
                last_print = time.time()

        print(f"\r{len(rx) // 2}/{len(samples)} samples "
              f"in {time.time() - start:.1f} s")

    if len(rx) % 2:
        rx = rx[:-1]
    return np.frombuffer(bytes(rx), dtype='<i2').astype(np.int16)


def main():
    ap = argparse.ArgumentParser(description="Filter a wav file on the FPGA.")
    ap.add_argument("wav", help="input .wav file")
    ap.add_argument("--port", default="COM5", help="serial port (default COM5)")
    ap.add_argument("--baud", type=int, default=1_000_000)
    ap.add_argument("--out", default="output.wav", help="filtered output .wav")
    ap.add_argument("--save-input", metavar="PATH",
                    help="also save the mono 8 kHz input that was sent")
    args = ap.parse_args()

    pcm, fs = wav_to_pcm(args.wav)
    print(f"Read {args.wav}: {len(pcm)} samples at {fs} Hz")
    samples = to_int16(resample(pcm, fs, FS_TARGET))
    print(f"Sending {len(samples)} samples at {FS_TARGET} Hz "
          f"({len(samples) / FS_TARGET:.1f} s of audio)")
    if args.save_input:
        write_wav(args.save_input, samples)

    hw = stream_through_fpga(samples, args.port, args.baud)
    write_wav(args.out, hw)
    print(f"Wrote {args.out}")

    # compare against the bit-accurate model
    expected = fir595(samples)
    n = min(len(hw), len(expected))
    bad = np.flatnonzero(hw[:n] != expected[:n])
    if len(hw) != len(expected):
        print(f"LENGTH MISMATCH: got {len(hw)}, expected {len(expected)}")
    if len(bad):
        i = bad[0]
        print(f"MISMATCH: {len(bad)} of {n} samples differ, first at index {i} "
              f"(hw={hw[i]}, model={expected[i]})")
        print("If every sample is wrong, the byte pairing may be off by one: "
              "press RESET and run again.")
    if len(bad) or len(hw) != len(expected):
        sys.exit(1)
    print(f"PASS: all {n} samples match fir_model.py")


if __name__ == "__main__":
    main()

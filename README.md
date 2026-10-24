# FGPA-FIR-Filter-and-Signal-Processor

`.wav → Python → UART → FPGA (5-9-5 FIR) → UART → Python → output.wav`
on an Arty S7-25 (xc7s25csga324-1), 100 MHz, UART 1 000 000 baud 8N1.
Samples are 16-bit signed, little-endian, 8 kHz.

## Files

| Path | What |
|---|---|
| `HLS/fir595.cpp/.h` | HLS source of the filter: `y = round((5x[n] + 9x[n-1] + 5x[n-2]) / 19)` |
| `rtl/fir595.v`, `rtl/fir595_ama_addmuladd_*.v` | HLS-generated Verilog (copied from `hls/syn/verilog`, do not edit) |
| `rtl/uart_rx.sv` / `rtl/uart_tx.sv` | 8N1 UART receiver / transmitter |
| `rtl/sample_assembler.sv` | 2 bytes (low, high) → 16-bit sample |
| `rtl/fir_ctrl.sv` | drives fir595's `ap_start/ap_done` handshake |
| `rtl/sample_fifo.sv` | 512-sample output buffer |
| `rtl/fir_uart_top.sv` | top level |
| `constraints/arty_s7_25.xdc` | pins and clock |
| `scripts/fir_model.py` | bit-accurate Python model + test-vector generator |
| `scripts/send_wav.py` | host script: wav → FPGA → output.wav, checks against the model |
| `sim/tb_fir_uart_top.sv`, `sim/run_sim.ps1` | top-level testbench (Vivado xsim) |

## Simulate

```powershell
powershell -ExecutionPolicy Bypass -File sim\run_sim.ps1
```
It ends with `PASS: 768/768 samples match fir_model.py`.

## Run on hardware

1. **Python packages:** the PyPI package called `serial` is a different library.
   You need `pyserial`:
   ```powershell
   pip uninstall serial
   pip install pyserial numpy
   ```
   (`scipy` is optional; `send_wav.py` uses it for resampling if installed.)
2. **Vivado project:** open `vivado project/FIR Filter and Signal Processor.xpr`
   (or make a new project).
   - *Settings → General → Project device:* `xc7s25csga324-1` (the project
     currently says `xc7s6ftgb196-1`, which is the wrong chip).
   - *Add Sources:* everything in `rtl/` (design sources).
   - *Add Constraints:* `constraints/arty_s7_25.xdc`.
   - Set `fir_uart_top` as the top module.
3. **Generate Bitstream**, then *Open Hardware Manager → Auto Connect → Program Device*.
   LED LD2 should blink (heartbeat).
4. Find the COM port: in Device Manager, the Arty shows up as **two** "USB Serial Port"
   entries. The UART is usually the one with the higher number.
5. Run:
   ```powershell
   python scripts/send_wav.py "wavFiles/Trip Taylor.wav" --port COM5 --out output.wav --save-input input_8k.wav
   ```
   Press the board's red **RESET** button when prompted. The script should print
   `PASS: all N samples match fir_model.py`. Listen to `input_8k.wav` vs `output.wav`:
   the output is low-pass filtered (slightly duller).

LEDs: LD2 heartbeat, LD3 RX activity, LD4 TX activity, LD5 output-FIFO overflow
(should never light up; if it does, press RESET).

**If every sample mismatches**, the high and low bytes are probably swapped
(for example, a stray byte arrived before the run). Press RESET and run again.

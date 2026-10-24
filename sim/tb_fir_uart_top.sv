// =============================================================================
// Testbench for fir_uart_top
// =============================================================================
// What this does, in plain terms:
//
//   1. Loads two files written by `python scripts/fir_model.py --gen-vectors`:
//        stim.hex     - input samples to send to the FPGA
//        expected.hex - what the Python model says the FIR should output
//   2. A "driver" acts like the PC: it wiggles the DUT's UART RX pin bit by
//      bit, sending each sample as two bytes (low byte first).
//   3. A "monitor" acts like the PC's receiver: it watches the DUT's UART TX
//      pin, decodes bytes, pairs them back into 16-bit samples.
//   4. A "scoreboard" compares each received sample with the next expected
//      sample and counts mismatches.
//   5. At the end it prints PASS or FAIL.
//
// The driver and monitor run in parallel (separate initial blocks), exactly
// like the real PC sending and receiving at the same time.
//
// Tests:
//   Test 1: send all samples back-to-back at the exact baud rate.
//   Test 2: press reset, send everything again. The expected output is the
//           same as test 1 only if reset really cleared the FIR's delay line
//           (test 1 ends on random samples, so leftover state would show up).
//   Test 3: reset, then send 2% FASTER than the FPGA transmits. The output
//           falls further and further behind the input, which exercises the
//           output FIFO (the "output lags input" case).
//
// Run with sim/run_sim.ps1 (Vivado xsim).
// =============================================================================
`timescale 1ns / 1ps

module tb_fir_uart_top;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam int  CLK_SPEED   = 100_000_000;
    localparam real CLK_PERIOD  = 10.0;                     // ns (100 MHz)
    localparam int  BAUDRATE    = 1_000_000;
    localparam real BIT_NS      = 1.0e9 / BAUDRATE;         // 1000 ns per bit
    localparam real TIMEOUT_NS  = 100.0e6;                  // 100 ms watchdog

    // Where the vector files live, relative to the directory xsim runs in
    // (sim/xsim_work). Override with the plusarg +VECTORS=<dir> if needed.
    string vectors_dir = "../vectors";

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic       clk = 1'b0;
    logic       ck_rst = 1'b0;      // active-low reset button, start pressed
    logic       pc_tx = 1'b1;       // PC -> FPGA line; UART idles high
    wire        pc_rx;              // FPGA -> PC line
    wire [3:0]  led;

    fir_uart_top #(
        .CLK_SPEED(CLK_SPEED),
        .BAUDRATE(BAUDRATE)
    ) dut (
        .CLK100MHZ(clk),
        .ck_rst(ck_rst),
        .uart_txd_in(pc_tx),
        .uart_rxd_out(pc_rx),
        .led(led)
    );

    // 100 MHz clock: toggle every half period
    always #(CLK_PERIOD / 2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Test vectors
    // -------------------------------------------------------------------------
    // SystemVerilog queues ($) are resizable arrays, handy when we don't know
    // the number of samples in advance.
    logic [15:0] stim[$];
    logic [15:0] expected[$];

    // Read one 4-digit hex value per line until end of file.
    task automatic load_hex(input string path, ref logic [15:0] q[$]);
        int fd;
        logic [15:0] value;
        fd = $fopen(path, "r");
        if (fd == 0) $fatal(1, "Cannot open %s (run fir_model.py --gen-vectors first)", path);
        while ($fscanf(fd, "%h\n", value) == 1) q.push_back(value);
        $fclose(fd);
        $display("[TB] Loaded %0d samples from %s", q.size(), path);
    endtask

    // -------------------------------------------------------------------------
    // Scoreboard
    // -------------------------------------------------------------------------
    // The test pushes the samples it expects into exp_q BEFORE sending. Every
    // time the monitor decodes a sample it pops the front of exp_q and
    // compares. Because the FIR produces exactly one output per input, in
    // order, a simple FIFO of expected values is all we need.
    logic [15:0] exp_q[$];
    int n_checked  = 0;
    int n_errors   = 0;
    int out_index  = 0;     // index within the current test, for messages

    function automatic void check_sample(input logic [15:0] got);
        logic [15:0] want;
        if (exp_q.size() == 0) begin
            $error("[SB] Got unexpected extra sample %0d (0x%04h)", $signed(got), got);
            n_errors++;
            return;
        end
        want = exp_q.pop_front();
        n_checked++;
        if (got !== want) begin
            n_errors++;
            // Only print the first few mismatches so the log stays readable
            if (n_errors <= 10)
                $error("[SB] Sample %0d: got %0d, expected %0d",
                       out_index, $signed(got), $signed(want));
        end
        out_index++;
    endfunction

    // -------------------------------------------------------------------------
    // Driver: the PC's transmitter (drives pc_tx)
    // -------------------------------------------------------------------------
    // 8N1 frame: start bit (0), 8 data bits LSB first, stop bit (1).
    // bit_ns lets a test send slightly fast or slow to model clock mismatch.
    task automatic uart_send_byte(input logic [7:0] b, input real bit_ns);
        pc_tx = 1'b0;                   // start bit
        #(bit_ns);
        for (int i = 0; i < 8; i++) begin
            pc_tx = b[i];               // data bits, LSB first
            #(bit_ns);
        end
        pc_tx = 1'b1;                   // stop bit
        #(bit_ns);
    endtask

    // WAV order: little-endian, so the low byte goes first.
    task automatic send_samples(input real bit_ns);
        foreach (stim[i]) begin
            uart_send_byte(stim[i][7:0],  bit_ns);
            uart_send_byte(stim[i][15:8], bit_ns);
        end
    endtask

    // -------------------------------------------------------------------------
    // Monitor: the PC's receiver (watches pc_rx)
    // -------------------------------------------------------------------------
    // Wait for the falling edge of a start bit, move to the middle of it, then
    // sample every bit in its middle (the most reliable point). Pair bytes
    // into samples and hand each sample to the scoreboard.
    initial begin : monitor
        logic [7:0]  rx_byte;
        logic [7:0]  low_byte;
        bit          have_low;
        have_low = 0;
        forever begin
            @(negedge pc_rx);           // start of start bit
            #(BIT_NS / 2);              // middle of start bit
            if (pc_rx !== 1'b0) continue;   // just a glitch, not a start bit
            for (int i = 0; i < 8; i++) begin
                #(BIT_NS);              // middle of data bit i
                rx_byte[i] = pc_rx;
            end
            #(BIT_NS);                  // middle of stop bit
            if (pc_rx !== 1'b1) begin
                $error("[MON] Framing error: stop bit is not 1");
                n_errors++;
            end
            // byte -> sample pairing (low byte first)
            if (!have_low) begin
                low_byte = rx_byte;
                have_low = 1;
            end else begin
                check_sample({rx_byte, low_byte});
                have_low = 0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Helpers for the test sequence
    // -------------------------------------------------------------------------
    // Hold the reset button for 1 us, then release and give the reset
    // synchronizer a few clocks.
    task automatic press_reset();
        ck_rst = 1'b0;
        #1000;
        ck_rst = 1'b1;
        repeat (10) @(posedge clk);
    endtask

    // Wait until the monitor has consumed every expected sample, plus one
    // extra frame of silence to make sure nothing else is coming.
    task automatic wait_for_outputs();
        while (exp_q.size() != 0) #(BIT_NS);
        #(BIT_NS * 20);
    endtask

    task automatic run_test(input string name, input real bit_ns);
        int errors_before = n_errors;
        $display("[TB] %s: sending %0d samples (bit time %.1f ns)",
                 name, stim.size(), bit_ns);
        press_reset();
        out_index = 0;
        foreach (expected[i]) exp_q.push_back(expected[i]);
        send_samples(bit_ns);
        $display("[TB] %s: all input sent at %.3f ms, %0d outputs still pending",
                 name, $realtime / 1.0e6, exp_q.size());
        wait_for_outputs();
        $display("[TB] %s: done at %.3f ms, %0d mismatches",
                 name, $realtime / 1.0e6, n_errors - errors_before);
    endtask

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------
    initial begin : main
        string arg;
        if ($value$plusargs("VECTORS=%s", arg)) vectors_dir = arg;
        load_hex({vectors_dir, "/stim.hex"}, stim);
        load_hex({vectors_dir, "/expected.hex"}, expected);
        if (stim.size() != expected.size() || stim.size() == 0)
            $fatal(1, "stim/expected size mismatch");

        run_test("Test 1 (exact baud)",        BIT_NS);
        run_test("Test 2 (after reset)",       BIT_NS);
        run_test("Test 3 (PC 2 pct fast)",    BIT_NS * 0.98);

        if (led[3]) begin
            $error("[TB] FIFO overflow LED is on");
            n_errors++;
        end

        $display("");
        $display("==================================================");
        if (n_errors == 0 && n_checked == 3 * expected.size())
            $display("  PASS: %0d/%0d samples match fir_model.py",
                     n_checked, 3 * expected.size());
        else
            $display("  FAIL: %0d errors, %0d/%0d samples checked",
                     n_errors, n_checked, 3 * expected.size());
        $display("==================================================");
        $finish;
    end

    // Watchdog: if something hangs (e.g. the DUT never answers), stop the
    // simulation instead of running forever.
    initial begin : watchdog
        #(TIMEOUT_NS);
        $fatal(1, "[TB] TIMEOUT: %0d samples still expected", exp_q.size());
    end

endmodule

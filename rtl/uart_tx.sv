// 8N1 UART transmitter. Same CLK_SPEED/BAUDRATE parameters and divisor
// formula as uart_rx, so both directions run at exactly the same bit period.
// Assert `start` while `busy` is low to send `data` (sampled that cycle).
module uart_tx #(
    parameter CLK_SPEED = 100_000_000,
    parameter int BAUDRATE = 921600
    )(
    input logic         clk,
    input logic         nrst,
    input logic[7:0]    data,
    input logic         start,

    output logic        tx,
    output logic        busy
);
localparam logic HIGH = 1'b1;
localparam logic LOW = 1'b0;

localparam CLK_PER_BIT = CLK_SPEED / BAUDRATE;

int clk_counter = 0;
int bit_counter = 0;
// frame = {stop, data[7:0], start}, shifted out LSB first.
// Bit 0 of this register IS the tx line (a flop output, so no glitches).
logic[9:0] frame_shift_register = '1;

assign tx = frame_shift_register[0];

always_ff @(posedge clk or negedge nrst) begin
    // reset logic
    if(!nrst) begin
        busy <= LOW;
        clk_counter <= 0;
        bit_counter <= 0;
        frame_shift_register <= '1; //idle line is high
    end
    // normal operation
    else begin
        if(!busy) begin
            if(start) begin
                frame_shift_register <= {HIGH, data, LOW};
                busy <= HIGH;
                clk_counter <= 0;
                bit_counter <= 0;
            end
        end
        else begin
            clk_counter <= clk_counter + 1;
            if(clk_counter >= CLK_PER_BIT - 1) begin //end of one bit period
                clk_counter <= 0;
                frame_shift_register <= {HIGH, frame_shift_register[9:1]};
                bit_counter <= bit_counter + 1;
            end
            // Release busy one cycle before the stop bit ends. The line is
            // still high (stop/idle), and a back-to-back start loads on the
            // next cycle, so the stop bit is exactly CLK_PER_BIT long and the
            // TX byte rate exactly matches uart_rx's byte rate.
            if(bit_counter == 9 && clk_counter >= CLK_PER_BIT - 2) begin
                busy <= LOW;
            end
        end
    end
end
endmodule

// Top level: UART in -> 5-9-5 FIR -> UART out, for the Arty S7-25.
//
//   uart_txd_in -> uart_rx -> sample_assembler -> fir_ctrl (fir595)
//               -> sample_fifo -> byte serializer -> uart_tx -> uart_rxd_out
//

module fir_uart_top #(
    parameter CLK_SPEED = 100_000_000,
    parameter int BAUDRATE = 1_000_000,
    parameter int FIFO_DEPTH = 512
    )(
    input logic         CLK100MHZ,
    input logic         ck_rst,         //active-low button
    input logic         uart_txd_in,    //PC -> FPGA
    output logic        uart_rxd_out,   //FPGA -> PC
    output logic[2:0]   led             //[0] RX activity, [1] TX activity, [2] FIFO overflow (sticky)
);
localparam logic HIGH = 1'b1;
localparam logic LOW = 1'b0;

logic clk;
assign clk = CLK100MHZ;

// Reset synchronizer: asserts immediately when the button is pressed,
// releases synchronously to clk so every flop leaves reset on the same edge.
logic rst_meta;
logic nrst;
always_ff @(posedge clk or negedge ck_rst) begin
    if(!ck_rst) begin
        rst_meta <= LOW;
        nrst <= LOW;
    end
    else begin
        rst_meta <= HIGH;
        nrst <= rst_meta;
    end
end

// UART receive + byte pairing
logic[7:0] rx_data;
logic rx_valid;
logic[15:0] x_sample;
logic x_valid;

uart_rx #(
    .CLK_SPEED(CLK_SPEED),
    .BAUDRATE(BAUDRATE)
) uart_rx_inst (
    .clk(clk),
    .nrst(nrst),
    .rx(uart_txd_in),
    .data(rx_data),
    .valid(rx_valid)
);

sample_assembler sample_assembler_inst (
    .clk(clk),
    .nrst(nrst),
    .byte_data(rx_data),
    .byte_valid(rx_valid),
    .sample(x_sample),
    .sample_valid(x_valid)
);

// FIR
logic[15:0] y_sample;
logic y_valid;

fir_ctrl fir_ctrl_inst (
    .clk(clk),
    .nrst(nrst),
    .x_in(x_sample),
    .x_valid(x_valid),
    .y_out(y_sample),
    .y_valid(y_valid)
);

// Output buffer
logic[15:0] fifo_data;
logic fifo_rd_en;
logic fifo_empty;
logic fifo_full;
logic fifo_overflow;

sample_fifo #(
    .WIDTH(16),
    .DEPTH(FIFO_DEPTH)
) sample_fifo_inst (
    .clk(clk),
    .nrst(nrst),
    .wr_data(y_sample),
    .wr_en(y_valid),
    .rd_en(fifo_rd_en),
    .rd_data(fifo_data),
    .empty(fifo_empty),
    .full(fifo_full),
    .overflow(fifo_overflow)
);

// Byte serializer: send the sample at the FIFO head as low byte, then high
// byte, then pop it. 
logic send_high_byte;
logic tx_start;
logic[7:0] tx_data;
logic tx_busy;

assign tx_start = !tx_busy && !fifo_empty;
assign tx_data = send_high_byte ? fifo_data[15:8] : fifo_data[7:0];
assign fifo_rd_en = tx_start && send_high_byte;

always_ff @(posedge clk or negedge nrst) begin
    if(!nrst) begin
        send_high_byte <= LOW;
    end
    else if(tx_start) begin
        send_high_byte <= !send_high_byte;
    end
end

uart_tx #(
    .CLK_SPEED(CLK_SPEED),
    .BAUDRATE(BAUDRATE)
) uart_tx_inst (
    .clk(clk),
    .nrst(nrst),
    .data(tx_data),
    .start(tx_start),
    .tx(uart_rxd_out),
    .busy(tx_busy)
);

// LEDs. Activity LEDs are stretched to ~20 ms so single bytes are visible.
localparam int LED_STRETCH = CLK_SPEED / 50;
int rx_led_counter;
int tx_led_counter;

always_ff @(posedge clk or negedge nrst) begin
    if(!nrst) begin
        rx_led_counter <= 0;
        tx_led_counter <= 0;
    end
    else begin
        if(rx_valid) rx_led_counter <= LED_STRETCH;
        else if(rx_led_counter != 0) rx_led_counter <= rx_led_counter - 1;
        if(tx_busy) tx_led_counter <= LED_STRETCH;
        else if(tx_led_counter != 0) tx_led_counter <= tx_led_counter - 1;
    end
end

assign led[0] = (rx_led_counter != 0);
assign led[1] = (tx_led_counter != 0);
assign led[2] = fifo_overflow;
endmodule


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
            
            if(bit_counter == 9 && clk_counter >= CLK_PER_BIT - 2) begin
                busy <= LOW;
            end
        end
    end
end
endmodule

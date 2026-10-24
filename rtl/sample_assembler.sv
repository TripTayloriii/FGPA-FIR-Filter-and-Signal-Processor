// Packs pairs of UART bytes into 16-bit samples, little-endian like WAV:
// the first byte after reset is the low byte, the second is the high byte.
// sample_valid pulses for one cycle when a full sample is ready.
module sample_assembler (
    input logic         clk,
    input logic         nrst,
    input logic[7:0]    byte_data,
    input logic         byte_valid,

    output logic[15:0]  sample,
    output logic        sample_valid
);
localparam logic HIGH = 1'b1;
localparam logic LOW = 1'b0;

logic have_low_byte;
logic[7:0] low_byte;

always_ff @(posedge clk or negedge nrst) begin
    // reset logic
    if(!nrst) begin
        have_low_byte <= LOW;
        low_byte <= '0;
        sample <= '0;
        sample_valid <= LOW;
    end
    // normal operation
    else begin
        sample_valid <= LOW;
        if(byte_valid) begin
            if(!have_low_byte) begin
                low_byte <= byte_data;
                have_low_byte <= HIGH;
            end
            else begin
                sample <= {byte_data, low_byte};
                sample_valid <= HIGH;
                have_low_byte <= LOW;
            end
        end
    end
end
endmodule

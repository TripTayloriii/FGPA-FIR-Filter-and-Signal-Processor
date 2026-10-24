// Wraps the HLS-generated fir595 block and drives its ap_ctrl_hs handshake:
//   - on x_valid: register the sample (fir595 has no input register of its
//     own) and raise ap_start
//   - drop ap_start when fir595 pulses ap_ready (it has taken the input)
//   - on ap_done: latch ap_return (it is only valid during that one cycle)
//     and pulse y_valid

module fir_ctrl (
    input logic         clk,
    input logic         nrst,
    input logic[15:0]   x_in,
    input logic         x_valid,

    output logic[15:0]  y_out,
    output logic        y_valid
);
localparam logic HIGH = 1'b1;
localparam logic LOW = 1'b0;

logic[15:0] x_reg;
logic ap_start;
logic ap_done;
logic ap_idle;
logic ap_ready;
logic[15:0] ap_return;

fir595 fir595_inst (
    .ap_clk(clk),
    .ap_rst(!nrst),     
    .ap_start(ap_start),
    .ap_done(ap_done),
    .ap_idle(ap_idle),
    .ap_ready(ap_ready),
    .x(x_reg),
    .ap_return(ap_return)
);

always_ff @(posedge clk or negedge nrst) begin
    // reset logic
    if(!nrst) begin
        x_reg <= '0;
        ap_start <= LOW;
        y_out <= '0;
        y_valid <= LOW;
    end
    // normal operation
    else begin
        y_valid <= LOW;

        if(x_valid) begin
            x_reg <= x_in;
            ap_start <= HIGH;
        end
        else if(ap_ready) begin
            ap_start <= LOW;
        end

        if(ap_done) begin
            y_out <= ap_return;
            y_valid <= HIGH;
        end
    end
end
endmodule

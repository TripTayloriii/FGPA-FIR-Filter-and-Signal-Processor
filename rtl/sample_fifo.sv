// Synchronous FIFO for filtered samples waiting to be sent over UART.

module sample_fifo #(
    parameter int WIDTH = 16,
    parameter int DEPTH = 512   //must be a power of 2
    )(
    input logic                 clk,
    input logic                 nrst,
    input logic[WIDTH-1:0]      wr_data,
    input logic                 wr_en,
    input logic                 rd_en,

    output logic[WIDTH-1:0]     rd_data,
    output logic                empty,
    output logic                full,
    output logic                overflow
);
localparam logic HIGH = 1'b1;
localparam logic LOW = 1'b0;
localparam int ADDR_BITS = $clog2(DEPTH);

// No reset on the storage, so Vivado can map it to distributed RAM.
logic[WIDTH-1:0] mem [DEPTH];
logic[ADDR_BITS-1:0] wr_ptr;
logic[ADDR_BITS-1:0] rd_ptr;
logic[ADDR_BITS:0] count;

assign rd_data = mem[rd_ptr];
assign empty = (count == 0);
assign full = (count == DEPTH);

logic do_write;
logic do_read;
assign do_write = wr_en && !full;
assign do_read = rd_en && !empty;

always_ff @(posedge clk) begin
    if(do_write) begin
        mem[wr_ptr] <= wr_data;
    end
end

always_ff @(posedge clk or negedge nrst) begin
    // reset logic
    if(!nrst) begin
        wr_ptr <= '0;
        rd_ptr <= '0;
        count <= '0;
        overflow <= LOW;
    end
    // normal operation
    else begin
        if(do_write) wr_ptr <= wr_ptr + 1'b1;
        if(do_read) rd_ptr <= rd_ptr + 1'b1;
        count <= count + do_write - do_read;
        if(wr_en && full) overflow <= HIGH;
    end
end
endmodule

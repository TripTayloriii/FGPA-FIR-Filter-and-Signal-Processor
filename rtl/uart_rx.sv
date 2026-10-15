module uart_rx #(
    parameter int BAUDRATE = 921600
    )(
    input logic         clk,
    input logic         nrst,
    input logic         rx,

    output logic[7:0]   data,
    output logic        valid
);
localparam logic HIGH = 1'b1;
localparam logic LOW = 1'b0;

typedef enum logic[1:0] { 
    IDLE,
    START,
    DATA,
    STOP
 } uart_state_t;

localparam CLK_PER_BIT = 100_000_000 / BAUDRATE;
localparam CLK_PER_HALFBIT = CLK_PER_BIT / 2;
int counter = 0;

uart_state_t uart_state = IDLE;
uart_state_t next_uart_state = uart_state;


// UART FSM
always_ff @(posedge clk or negedge nrst ) begin
    if(!nrst) begin
        uart_state <= IDLE;
        counter <= 0;
    end
    else begin
        case (uart_state) 
            uart_state <= next_uart_state;
        endcase
    end
end

always_comb begin
    case (uart_state) 
        IDLE: 
            data = '0;
            valid = LOW;
            next_uart_state = IDLE;
            if(rx == LOW) begin
                next_uart_state = START;
            end
        START:
            next_uart_state = START;
            if(counter >= CLK_PER_HALFBIT && rx == LOW) begin
                next_uart_state = DATA;
            end
        DATA:

        STOP:
 
    endcase
end
endmodule

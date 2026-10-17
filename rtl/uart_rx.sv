module uart_rx #(
    parameter CLK_SPEED = 100_000_000,
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

localparam CLK_PER_BIT = CLK_SPEED / BAUDRATE;
localparam CLK_PER_HALFBIT = CLK_PER_BIT / 2;
logic rx_meta;
logic rx_sync;
int clk_counter = 0;
int bit_counter = 0;
logic[7:0] data_shift_register = '0;
uart_state_t uart_state = IDLE;
uart_state_t next_uart_state = uart_state;


// UART FSM
always_ff @(posedge clk or negedge nrst ) begin
    // reset logic
    if(!nrst) begin
        uart_state <= IDLE;
        rx_meta <= HIGH;
        rx_sync <= HIGH;
        data_shift_register <= '0;
        data <= '0;
        clk_counter <= 0;
        bit_counter <= 0;
        valid <= LOW;
    end
    // normal operation
    else begin
        rx_meta <= rx;
        rx_sync <= rx_meta; 
        //counter logic
        if(uart_state == START || uart_state == DATA || uart_state == STOP) begin
            clk_counter <= clk_counter + 1;
            if(clk_counter >= CLK_PER_BIT - 1) begin
                clk_counter <= 0;
                bit_counter <= bit_counter + 1;
            end
        end

        case(uart_state)
            IDLE: begin
                valid <= LOW;
            end

            DATA: begin
                if(clk_counter == CLK_PER_BIT - 1) begin
                    data_shift_register <= {rx_sync, data_shift_register[7:1]};
                end
            end

            STOP: begin
                if(clk_counter >= CLK_PER_BIT - 1 && rx_sync == HIGH) begin //verify stop bit and writing data
                    data <= data_shift_register;
                    valid <= HIGH;
                end
            end

        endcase

        //reset counters on state change
        if(uart_state != next_uart_state) begin 
            clk_counter <= 0;
            bit_counter <= 0;
        end

        uart_state <= next_uart_state;
        
    end
end

always_comb begin
    // default values
    next_uart_state = uart_state;

    case (uart_state) 
        IDLE: begin 
            if(rx_sync == LOW) begin
                next_uart_state = START;
            end
        end

        START: begin
            if(clk_counter >= CLK_PER_HALFBIT) begin
                if(rx_sync == LOW) begin
                    next_uart_state = DATA;
                end
                else begin
                    next_uart_state = IDLE;
                end
            end
        end

        DATA: begin
            if(bit_counter == 7 && clk_counter == CLK_PER_BIT - 1) begin
                next_uart_state = STOP;
            end
        end

        STOP: begin //stop bit is HIGH
            if(clk_counter >= CLK_PER_BIT - 1) begin
                next_uart_state = IDLE;
            end
        end

    endcase
end
endmodule

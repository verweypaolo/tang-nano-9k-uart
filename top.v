`default_nettype none

module top (
    input  clk,
    input  uart_rx,
    output uart_tx,
    output [5:0] led,
    input  btn1
);

uart uart_inst (
    .clk(clk),
    .uart_rx(uart_rx),
    .uart_tx(uart_tx),
    .led(led),
    .btn1(btn1)
);

endmodule

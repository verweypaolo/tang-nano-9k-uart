module test();
    reg clk = 0;
    reg uart_rx = 1;
    wire uart_tx;
    wire [5:0] led;
    reg btn = 1;
    // override delay frames, easier to look at only 8 clock pulses in simulation
    uart #(8'd8) u(
        clk,
        uart_rx,
        uart_tx,
        led,
        btn
    );

always
    #1 clk = ~clk; //#1 is iverilog simulation syntax; allows us to delay something by n time frames, toggles clock register every time unit to simulate clock

initial begin
    $display("Starting UART RX");
    $monitor("LED Value %b", led);
    #10 uart_rx=0; // start, delay 10 time frames
    #16 uart_rx=1; // delay 16 time frames, 8 clock cycles matches 8'd8
    #16 uart_rx=0;
    #16 uart_rx=0;
    #16 uart_rx=0;
    #16 uart_rx=0;
    #16 uart_rx=1;
    #16 uart_rx=1;
    #16 uart_rx=0;
    #16 uart_rx=1; // stop
  #1000 $finish;
end

initial begin
    $dumpfile("uart.vcd");
    $dumpvars(0,test);
end

endmodule
// doesn't receive any outside inputs, but creates all the inputs that the module we want to test requires, 
// then creates an instance of that module